# workaround before build.zig in use
zig build-exe src/main.zig -O ReleaseFast -fstrip -target wasm32-wasi
rm *.wasm.o && mv main.wasm zig-out/bin
npx wrangler@wasm publish --dry-run --compatibility-date 2024-10-19 --name dot-minify zig-out/bin/main.wasm