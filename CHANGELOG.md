# Changelog

## 2.0.0 (unreleased)

- Serde now uses a versioned binary format. Data written by older versions must be serialized again.
- Serde preserves instance references, parent paths, non-creatable instances, nil properties, attributes, buffers, and all common Roblox datatypes.
- Serde validates its input and rejects truncated, oversized, or malformed data with an error.
- `Maid:Link` destroys the maid. The old cleanup behavior is available as `Maid:LinkCleanup`.
- `Event` connections now remove only their own callback when the same function is connected twice.
- `Event.new` and `Maid.new` remain available as aliases for `Event.New` and `Maid.New`.
- `Interface.New` copies its initial storage instead of sharing the caller's table.
- `Deque.Push` and `Deque.PushFront` reject `nil` values so an empty queue stays distinguishable.
- `Cache:To` only updates the in-memory cache after the file write succeeds.
- `Vec` compression preserves the original bit length and can decompress a `Vec` or a `buffer`.
- `Vec.FromBuffer` copies the input buffer.
- Removed `Flate`; use `Vec:Compress` and `Vec.Decompress` instead.
