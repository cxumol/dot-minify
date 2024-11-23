# test
zig test src/test.zig

# wasm
zig build-exe src/main.zig -O ReleaseFast -fstrip -target wasm32-wasi
zig build -Doptimize=ReleaseFast -Dtarget=wasm32-wasi --summary all
rm *.wasm.o && mv main.wasm zig-out/bin
npx wrangler@wasm publish --dry-run --compatibility-date 2024-11-18 --name dot-minify zig-out/bin/main.wasm
npx wrangler@wasm publish --dry-run --compatibility-date 2024-11-18 --name dot-minify zig-out/bin/dot-minify.wasm

# regular
zig build-exe src/main.zig -O ReleaseSmall -fstrip -fsingle-threaded -target x86_64-linux
zig build-exe src/main.zig -O ReleaseSafe -fstrip -fsingle-threaded -target x86_64-linux
zig build -Doptimize=ReleaseSafe --release=small --summary all
zig build -Doptimize=ReleaseSmall --summary all