# Vendored CompactSlider

This is [CompactSlider](https://github.com/buh/CompactSlider) 1.2.1
(revision `e5219ff353613b6493bfe5a3333c3bfa2d1e4d57`), MIT-licensed (see `LICENSE`),
copied here as a local Swift package.

It is vendored because no 1.x release compiles with the Xcode 27 SDK: the gradient
background in `ProminentCompactSliderStyle.swift` hits an ambiguous `opacity` call
(`View.opacity` vs `ShapeStyle.opacity`). 2.x compiles, but has a different API.

Local changes:

- `Sources/CompactSlider/ProminentCompactSliderStyle.swift`: the gradient background is
  wrapped in `Rectangle().fill(...)` so `opacity` resolves to `View.opacity`.

Only `Package.swift`, `Sources/`, `LICENSE` and `README.md` were copied.
