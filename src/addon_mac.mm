/**
 * electron-native-mac-noti
 * Native macOS notification support with contentImage using UNUserNotificationCenter
 */

#include "napi.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#include <map>
#include <mutex>
#include <string>

// Store callbacks for notification events
struct CallbackData {
    Napi::ThreadSafeFunction tsfn;
    std::string userInfo;
};
static std::map<std::string, CallbackData> g_callbacks;
static std::mutex g_callbacksMutex;

// Invoke callback helper - runs on Node.js thread
static void invokeCallback(const std::string& identifier, const std::string& eventType, const std::string& userInfo) {
    std::lock_guard<std::mutex> lock(g_callbacksMutex);
    auto it = g_callbacks.find(identifier);
    if (it != g_callbacks.end()) {
        std::string capturedEvent = eventType;
        std::string capturedUserInfo = userInfo;
        
        it->second.tsfn.NonBlockingCall([capturedEvent, capturedUserInfo](Napi::Env env, Napi::Function jsCallback) {
            Napi::HandleScope scope(env);
            jsCallback.Call({
                Napi::String::New(env, capturedEvent),
                Napi::String::New(env, capturedUserInfo)
            });
        });
        
        // Release and clean up after click
        it->second.tsfn.Release();
        g_callbacks.erase(it);
    }
}

// Notification delegate
@interface NotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation NotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // Show notification even when app is in foreground
    if (@available(macOS 11.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
    } else {
        completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    
    NSString *identifier = response.notification.request.identifier;
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    NSString *customData = userInfo[@"customData"];
    
    std::string identifierStr = identifier ? [identifier UTF8String] : "";
    std::string userInfoStr = customData ? [customData UTF8String] : "";
    
    // Invoke callback on Node.js thread
    invokeCallback(identifierStr, "click", userInfoStr);
    
    completionHandler();
}

@end

// Singleton delegate instance
static NotificationDelegate *g_delegate = nil;

void ensureDelegate() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_delegate = [[NotificationDelegate alloc] init];
        [[UNUserNotificationCenter currentNotificationCenter] setDelegate:g_delegate];
    });
}

// Check if available (macOS 10.14+)
Napi::Value IsAvailable(const Napi::CallbackInfo& info) {
    return Napi::Boolean::New(info.Env(), true);
}

// Async worker for requesting permission
class RequestPermissionWorker : public Napi::AsyncWorker {
public:
    RequestPermissionWorker(Napi::Env env, Napi::Promise::Deferred deferred)
        : Napi::AsyncWorker(env), deferred_(deferred), granted_(false) {}
    
    void Execute() override {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                                  completionHandler:^(BOOL granted, NSError * _Nullable error) {
                granted_ = granted;
                dispatch_semaphore_signal(semaphore);
            }];
        });
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    
    void OnOK() override {
        Napi::HandleScope scope(Env());
        deferred_.Resolve(Napi::Boolean::New(Env(), granted_));
    }
    
    void OnError(const Napi::Error& error) override {
        Napi::HandleScope scope(Env());
        deferred_.Reject(error.Value());
    }
    
private:
    Napi::Promise::Deferred deferred_;
    bool granted_;
};

// Request notification permission
Napi::Value RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    
    auto* worker = new RequestPermissionWorker(env, deferred);
    worker->Queue();
    
    return deferred.Promise();
}

// Async worker for getting permission status
class GetPermissionStatusWorker : public Napi::AsyncWorker {
public:
    GetPermissionStatusWorker(Napi::Env env, Napi::Promise::Deferred deferred)
        : Napi::AsyncWorker(env), deferred_(deferred), status_("notDetermined") {}
    
    void Execute() override {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
                switch (settings.authorizationStatus) {
                    case UNAuthorizationStatusAuthorized:
                    case UNAuthorizationStatusProvisional:
                        status_ = "granted";
                        break;
                    case UNAuthorizationStatusDenied:
                        status_ = "denied";
                        break;
                    default:
                        status_ = "notDetermined";
                        break;
                }
                dispatch_semaphore_signal(semaphore);
            }];
        });
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    
    void OnOK() override {
        Napi::HandleScope scope(Env());
        deferred_.Resolve(Napi::String::New(Env(), status_));
    }
    
    void OnError(const Napi::Error& error) override {
        Napi::HandleScope scope(Env());
        deferred_.Reject(error.Value());
    }
    
private:
    Napi::Promise::Deferred deferred_;
    std::string status_;
};

// Get permission status
Napi::Value GetPermissionStatus(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    
    auto* worker = new GetPermissionStatusWorker(env, deferred);
    worker->Queue();
    
    return deferred.Promise();
}

// Async worker for showing notification
class ShowNotificationWorker : public Napi::AsyncWorker {
public:
    ShowNotificationWorker(Napi::Env env, Napi::Promise::Deferred deferred,
                          const std::string& title, const std::string& subtitle,
                          const std::string& body, const std::string& contentImage,
                          const std::string& identifier, const std::string& userInfo,
                          bool playSound)
        : Napi::AsyncWorker(env), deferred_(deferred),
          title_(title), subtitle_(subtitle), body_(body),
          contentImage_(contentImage), identifier_(identifier),
          userInfo_(userInfo), playSound_(playSound),
          success_(false), errorMessage_("") {}
    
    void Execute() override {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
                content.title = [NSString stringWithUTF8String:title_.c_str()];
                
                if (!subtitle_.empty()) {
                    content.subtitle = [NSString stringWithUTF8String:subtitle_.c_str()];
                }
                
                if (!body_.empty()) {
                    content.body = [NSString stringWithUTF8String:body_.c_str()];
                }
                
                if (playSound_) {
                    content.sound = [UNNotificationSound defaultSound];
                }
                
                // Store custom data in userInfo
                if (!userInfo_.empty()) {
                    content.userInfo = @{@"customData": [NSString stringWithUTF8String:userInfo_.c_str()]};
                }
                
                // Add contentImage as attachment
                if (!contentImage_.empty()) {
                    @try {
                        NSString *imagePath = [NSString stringWithUTF8String:contentImage_.c_str()];
                        if (imagePath) {
                            NSURL *imageURL = [NSURL fileURLWithPath:imagePath];
                            
                            if (imageURL && [[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
                                NSError *attachmentError = nil;
                                UNNotificationAttachment *attachment = [UNNotificationAttachment 
                                    attachmentWithIdentifier:@"contentImage"
                                    URL:imageURL
                                    options:@{UNNotificationAttachmentOptionsTypeHintKey: (__bridge NSString *)kUTTypePNG}
                                    error:&attachmentError];
                                
                                if (attachment && !attachmentError) {
                                    content.attachments = @[attachment];
                                } else if (attachmentError) {
                                    NSLog(@"[electron-native-mac-noti] Failed to create attachment: %@", attachmentError);
                                }
                            } else {
                                NSLog(@"[electron-native-mac-noti] Image file not found: %@", imagePath);
                            }
                        }
                    } @catch (NSException *exception) {
                        NSLog(@"[electron-native-mac-noti] Exception creating attachment: %@", exception);
                    }
                }
                
                // Create request with immediate trigger
                UNNotificationRequest *request = [UNNotificationRequest 
                    requestWithIdentifier:[NSString stringWithUTF8String:identifier_.c_str()]
                    content:content
                    trigger:nil];
                
                // Add notification
                [[UNUserNotificationCenter currentNotificationCenter] 
                    addNotificationRequest:request
                    withCompletionHandler:^(NSError * _Nullable error) {
                        if (error) {
                            success_ = false;
                            NSString *errorDesc = [error localizedDescription];
                            errorMessage_ = errorDesc ? [errorDesc UTF8String] : "Unknown error";
                        } else {
                            success_ = true;
                        }
                        dispatch_semaphore_signal(semaphore);
                    }];
            }
        });
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    
    void OnOK() override {
        Napi::HandleScope scope(Env());
        Napi::Object result = Napi::Object::New(Env());
        result.Set("success", Napi::Boolean::New(Env(), success_));
        if (!success_) {
            result.Set("error", Napi::String::New(Env(), errorMessage_));
        } else {
            result.Set("identifier", Napi::String::New(Env(), identifier_));
        }
        deferred_.Resolve(result);
    }
    
    void OnError(const Napi::Error& error) override {
        Napi::HandleScope scope(Env());
        deferred_.Reject(error.Value());
    }
    
private:
    Napi::Promise::Deferred deferred_;
    std::string title_;
    std::string subtitle_;
    std::string body_;
    std::string contentImage_;
    std::string identifier_;
    std::string userInfo_;
    bool playSound_;
    bool success_;
    std::string errorMessage_;
};

// Show notification
Napi::Value ShowNotification(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    ensureDelegate();
    
    if (info.Length() < 1 || !info[0].IsObject()) {
        Napi::TypeError::New(env, "Expected options object").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    auto options = info[0].As<Napi::Object>();
    
    // Get title (required)
    if (!options.Has("title") || !options.Get("title").IsString()) {
        Napi::TypeError::New(env, "title is required").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string title = options.Get("title").As<Napi::String>().Utf8Value();
    
    // Get optional fields
    std::string subtitle = "";
    if (options.Has("subtitle") && options.Get("subtitle").IsString()) {
        subtitle = options.Get("subtitle").As<Napi::String>().Utf8Value();
    }
    
    std::string body = "";
    if (options.Has("body") && options.Get("body").IsString()) {
        body = options.Get("body").As<Napi::String>().Utf8Value();
    }
    
    std::string contentImage = "";
    if (options.Has("contentImage") && options.Get("contentImage").IsString()) {
        contentImage = options.Get("contentImage").As<Napi::String>().Utf8Value();
    }
    
    std::string identifier = "";
    if (options.Has("identifier") && options.Get("identifier").IsString()) {
        identifier = options.Get("identifier").As<Napi::String>().Utf8Value();
    } else {
        // Generate unique identifier
        identifier = [[NSUUID UUID].UUIDString UTF8String];
    }
    
    std::string userInfo = "";
    if (options.Has("userInfo") && options.Get("userInfo").IsString()) {
        userInfo = options.Get("userInfo").As<Napi::String>().Utf8Value();
    }
    
    bool playSound = true;
    if (options.Has("sound") && options.Get("sound").IsBoolean()) {
        playSound = options.Get("sound").As<Napi::Boolean>().Value();
    }
    
    // Store callback if provided
    if (info.Length() > 1 && info[1].IsFunction()) {
        auto tsfn = Napi::ThreadSafeFunction::New(
            env,
            info[1].As<Napi::Function>(),
            "NotificationCallback",
            0,
            1
        );
        
        std::lock_guard<std::mutex> lock(g_callbacksMutex);
        // Release old callback if exists
        auto it = g_callbacks.find(identifier);
        if (it != g_callbacks.end()) {
            it->second.tsfn.Release();
            g_callbacks.erase(it);
        }
        g_callbacks[identifier] = {std::move(tsfn), userInfo};
    }
    
    // Create promise and start worker
    auto deferred = Napi::Promise::Deferred::New(env);
    auto* worker = new ShowNotificationWorker(env, deferred, title, subtitle, body,
                                              contentImage, identifier, userInfo, playSound);
    worker->Queue();
    
    return deferred.Promise();
}

// Remove notification by identifier
Napi::Value RemoveNotification(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "Expected identifier string").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    std::string identifier = info[0].As<Napi::String>().Utf8Value();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *identifiers = @[[NSString stringWithUTF8String:identifier.c_str()]];
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:identifiers];
        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:identifiers];
    });
    
    // Clean up callback
    {
        std::lock_guard<std::mutex> lock(g_callbacksMutex);
        auto it = g_callbacks.find(identifier);
        if (it != g_callbacks.end()) {
            it->second.tsfn.Release();
            g_callbacks.erase(it);
        }
    }
    
    return env.Undefined();
}

// Remove all notifications
Napi::Value RemoveAllNotifications(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
        [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
    });
    
    // Clean up all callbacks
    {
        std::lock_guard<std::mutex> lock(g_callbacksMutex);
        for (auto& pair : g_callbacks) {
            pair.second.tsfn.Release();
        }
        g_callbacks.clear();
    }
    
    return env.Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("isAvailable", Napi::Function::New(env, IsAvailable));
    exports.Set("requestPermission", Napi::Function::New(env, RequestPermission));
    exports.Set("getPermissionStatus", Napi::Function::New(env, GetPermissionStatus));
    exports.Set("showNotification", Napi::Function::New(env, ShowNotification));
    exports.Set("removeNotification", Napi::Function::New(env, RemoveNotification));
    exports.Set("removeAllNotifications", Napi::Function::New(env, RemoveAllNotifications));
    return exports;
}

NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
