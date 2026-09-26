import { harTasks } from '@ohos/hvigor-ohos-plugin';
import { cargoPlugin } from '@openharmony-rs/hvigor-cargo';

export default {
  system: harTasks,
  plugins: [
    cargoPlugin({
      manifestPath: '../crates/napi/Cargo.toml',
      // An unoptimized Servo is too slow to be useful, even for debugging the app.
      profiles: { debug: 'release', release: 'release' },
      ohosArgs: ['--download-prebuilt=19'],
      // Host compilers for the build scripts of mozjs.
      env: {
        CC: 'clang',
        CXX: 'clang++',
        HOST_CC: 'clang',
        HOST_CXX: 'clang++',
        HOST_CFLAGS: '',
        HOST_CXXFLAGS: '',
      },
    }),
  ],
}
