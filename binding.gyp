{
  'targets': [
    {
      'target_name': 'electron_native_mac_noti',
      'dependencies': [
        "<!(node -p \"require('node-addon-api').targets\"):node_addon_api_except",
      ],
      'cflags_cc': ['-std=c++20'],
      'conditions': [
        ['OS=="mac"', {
          'cflags+': ['-fvisibility=hidden'],
          'xcode_settings': {
            'GCC_SYMBOLS_PRIVATE_EXTERN': 'YES',
          }
        }],
        ['OS=="mac"', {
          'sources': ['src/addon_mac.mm'],
          'xcode_settings': {
            'OTHER_CFLAGS': ['-mmacos-version-min=10.14', '-std=c++20', '-fobjc-arc'],
            'OTHER_LDFLAGS': ['-framework Foundation', '-framework AppKit', '-framework UserNotifications'],
            'GCC_GENERATE_DEBUGGING_SYMBOLS': 'YES',
            'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym',
          },
        },
        {
          'sources': ['src/addon_none.cc'],
        }],
      ],
    },
  ],
}
