# Recognition runtime checks

`test-recognition.sh APP_PATH` exercises the app's actual CPU image renderer,
Vision face detector, head-angle extraction, five-point alignment, and ArcFace
embedder using the compiled model inside the provided app bundle. It also checks
that a blank image does not produce a face. This does not test camera hardware,
live enrollment, Keychain, lock-screen integration, or biometric accuracy.

The fixture is scikit-image v0.24.0's public-domain NASA astronaut image. The
script verifies its published SHA-256 before reading it. The fixture is temporary
and is not bundled with Glance. No user photos are used by this workflow.

- Provenance: https://github.com/scikit-image/scikit-image/blob/v0.24.0/skimage/data/_fetchers.py
- Published checksum: https://github.com/scikit-image/scikit-image/blob/v0.24.0/skimage/data/_registry.py

The Intel port uses CPU rendering and CPU Core ML inference. Enrollment retains
the existing quality, alignment, pose, and hold requirements. Processing failures
are displayed with a Show details control rather than classified as no face.
