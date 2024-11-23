# test
zig test src/test.zig

# wasm
zig build-exe src/main.zig -O ReleaseFast -fstrip -target wasm32-wasi
rm *.wasm.o && mv main.wasm zig-out/bin
npx wrangler@wasm publish --dry-run --compatibility-date 2024-10-19 --name dot-minify zig-out/bin/main.wasm
# regular
zig build-exe src/main.zig -O ReleaseSmall -fstrip -fsingle-threaded -target x86_64-linux
zig build-exe src/main.zig -O ReleaseSafe -fstrip -fsingle-threaded -target x86_64-linux
zig build -Doptimize=ReleaseSafe --release=small --summary all
zig build -Doptimize=ReleaseSmall -fstrip -fsingle-threaded --summary all