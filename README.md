# zig-set-version

Build extension for updating sem-version in build.zig.zon

## Requirement

* Zig 0.14.0 or latter.

## Instration

You can use `zig fetch`command to install it.

```
zig fetch --save=set_version git+https://github.com/ritalin/zig-set-version
```

Then add the following to `build.zig`.

```zig
pub fn build(b: *std.Build) void {
    @import("set_version").VersionSetterStep.addStep(b);
    // (snip)
}
```

## Features

* Show current version in this project
* Replace to specified version
* Increlent version

## Usage

### Showing version

```zig
$ zig build version -- show
0.0.0
```

### Replacing version

```zig
$ zig build version -- renew 1.2.3
Updated to `1.2.3`
```

### Incrementing version

> [!WARNING]
> One of `--major`, `--minor` and `--patch` must be specifed.

```zig
$ zig build version -- show
1.2.3
$ zig build version -- inc --patch
Updated to `1.2.4`
```

```zig
$ zig build version -- show
1.2.3
$ zig build version -- inc --minor
Updated to `1.3.0`
```

```zig
$ zig build version -- show
1.2.3
$ zig build version -- inc --major
Updated to `2.0.0`
```

> [!TIP]
> `--keep-pre` and `--keep-build` is optional.
> You can use specify it to keep `pre` part and `build` part.
> If you don't only specify `--keep-pre`, `build` part is also discarded.

```zig
$ zig build version -- show
1.2.3-alpha+2048
$ zig build version -- inc --patch --keep-pre --keep-build
Updated to `1.2.4-alpha+2048`
```

```zig
$ zig build version -- show
1.2.3-alpha+2048
$ zig build version -- inc --patch --keep-pre
Updated to `1.2.4-alpha`
```
