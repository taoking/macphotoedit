# Similar Photo Large-Library Benchmark

## Run the developer report

In a debug/development build, choose **File → 运行相似照片基准（开发者）**.
The app writes a timestamped `similar-photo-benchmark-*.txt` report to its
Application Support `logs` directory and reveals it in Finder.

The command intentionally executes two different workloads:

1. **Live media** — scans the current available Catalog with its actual
   security-scoped source paths. This can measure candidate fetch, cache reuse,
   new dHash/ImageIO decode work, grouping, total time, failures and sampled
   resident memory.
2. **Catalog-only** — creates disposable, isolated SQLite Catalogs containing
   10,000, 50,000 and 100,000 generated photo rows. It measures Catalog
   population/fetch and dHash-grouping data structures only. It does not open
   an image, decode ImageIO data, access a volume or claim real-media results.

The command reads but never writes, moves, deletes or overwrites source media.
Its temporary generated Catalogs are removed when each scale ends.

## Interpreting results

There are no fixed time assertions. Record the Mac model, macOS version,
available memory, storage type, whether the live run was cold/warm and image
formats before comparing reports.

The 10k/50k/100k generated results prove that those Catalog-row scales ran;
they do **not** prove that a library with the same number of JPEG, HEIC, TIFF
or RAW-derived images hashes at the same rate. A live-media report lists actual
ImageIO decode attempts and must be cited separately.

## Index behavior

Small Catalogs use the local dHash BK-tree. A sampled 50k random-hash profile
showed BK-tree range traversal dominating grouping CPU, so Catalogs with at
least 25k entries use an exact 4×16-bit Hamming candidate index for the current
distance-8 review threshold. A pair no more than eight bits apart must have one
16-bit block differing in no more than two bits; the index enumerates those
block variants and still exact-checks the complete dHash before grouping.

This is an implementation-scale optimization, not AI, semantic recognition,
face analysis, cloud processing or an automatic deletion rule.

## Manual follow-up

Use the checklist in `docs/manual-validation.md` on authorized real media and
physical storage. Exercise cancellation while images are hashing, switch roots,
cancel during grouping, repeat with unchanged signatures, then change
modification time and file size and confirm exactly the changed sources rehash.
Disconnect a removable root and confirm it becomes offline without receiving a
fallback hash or losing Catalog state.
