/**
 * This file implements a facade of the addon for platforms that are not
 * supported (Windows, Linux).
 */

#include <napi.h>

Napi::Value IsAvailable(const Napi::CallbackInfo& info) {
    return Napi::Boolean::New(info.Env(), false);
}

Napi::Value RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    deferred.Resolve(Napi::Boolean::New(env, false));
    return deferred.Promise();
}

Napi::Value GetPermissionStatus(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    deferred.Resolve(Napi::String::New(env, "denied"));
    return deferred.Promise();
}

Napi::Value ShowNotification(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    auto deferred = Napi::Promise::Deferred::New(env);
    
    Napi::Object result = Napi::Object::New(env);
    result.Set("success", Napi::Boolean::New(env, false));
    result.Set("error", Napi::String::New(env, "Native notifications not available on this platform"));
    
    deferred.Resolve(result);
    return deferred.Promise();
}

Napi::Value RemoveNotification(const Napi::CallbackInfo& info) {
    return info.Env().Undefined();
}

Napi::Value RemoveAllNotifications(const Napi::CallbackInfo& info) {
    return info.Env().Undefined();
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
