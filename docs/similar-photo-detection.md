# Similar Photo Detection

## Scope

Phase 15 adds a local perceptual-similarity review tool. It is separate from
the existing exact-duplicate SHA-256 scan:

- Exact duplicate detection proves equal source bytes only after same-size
  candidate grouping.
- Similar photo detection decodes every currently available Catalog photo with
  ImageIO and computes a 64-bit dHash from a 9×8 luminance sample.

dHash preserves left-to-right brightness relationships, so it is useful for
resized copies, JPEG re-exports/recompression and uniform, small exposure or
colour shifts. It is not semantic search, face recognition, proof of identity
or a deletion recommendation.

## Local-only data flow

```text
User starts “查找相似照片”
→ security-scoped read of referenced original
→ ImageIO thumbnail (maximum 96 px)
→ 9×8 local raster → 64-bit dHash
→ Catalog cache + local Hamming grouping
→ Similar Group / similarity score review UI
```

No source file is copied, edited, moved, deleted or uploaded. The Catalog
stores only a 16-character dHash digest, its algorithm name, source file size,
source modification time and computation timestamp. A changed file size or
modification time invalidates the cached digest automatically. If ImageIO or
rasterization fails, that asset is reported as not analysed and never receives
a fabricated fallback hash.

## Grouping and score

The current review threshold is Hamming distance `≤ 8` out of 64 dHash bits.
The UI score is `(64 - distance) / 64 × 100`, rounded to an integer. It is a
pixel-structure proximity score, not a probability that two photos are the
same scene.

A BK-tree indexes Hamming distance for smaller Catalogs; duplicate digest nodes
use one representative edge to keep large duplicate/burst clusters from
expanding quadratically. Profiling a 50k generated, high-entropy dHash Catalog
showed the BK-tree range traversal becoming the grouping hotspot. For Catalogs
at or above 25k records (with the current threshold `≤ 8`), the app therefore
uses an exact local 4×16-bit Hamming index instead: any pair differing by at
most eight bits must differ by at most two bits in at least one 16-bit block.
All 0–2-bit variants of each block are fetched and every returned candidate is
then checked against the complete 64-bit Hamming distance. This has no false
negatives for the threshold and is neither semantic nor cloud search.

Similar groups are connected components, so a member may be connected
transitively. The UI shows the comparison edges that formed the group, rather
than pretending every member has been directly compared with every other
member.

## Visual review workflow

The Similar Group sheet presents every Catalog-backed member as a compact card
with a `ThumbnailStore` image limited to 256 pixels, rather than opening a
full-resolution original. Each card shows filename, pixel dimensions, Catalog
file size, rating, flag, RAW/JPEG format indicator and capture date. If a
Catalog record is unavailable, the sheet reports that state without attempting
to decode the source file.

Review selection is local to the sheet and can be used for only the following
explicit actions: select the corresponding Library item, open its thumbnail
preview, set 0–5 stars, Pick/Reject/clear flag, add to an existing manual
album, create a stack, or move available selected items to Trash. Moving to
Trash always requires the system confirmation dialog; it is never inferred
from a similarity score. All actions reuse the normal Library services, so the
same availability and referenced-source safeguards apply.

There is deliberately no keeper ranking or automatic non-keeper action. A
similarity score is an inspection aid, not an AI best-photo decision.

## Instrumentation and developer benchmark

Each similarity scan reports candidate-fetch time, hash reuse/new-hash counts,
ImageIO decode attempts and time, grouping time, total time, group/failure
counts and an observed process resident-memory sample. These are diagnostics,
not pass/fail thresholds: storage speed, image formats, cache warmth and
hardware all affect them.

Use **File → 运行相似照片基准（开发者）** to write a text report under the
app's Application Support `logs` directory. It has two deliberately separate
sections:

- **Live-media scan** reads the current available Catalog photos through their
  security-scoped roots and is the only section that may measure actual
  ImageIO/dHash work.
- **Catalog-only generated scales** create and remove isolated temporary SQLite
  Catalogs with 10,000, 50,000 and 100,000 synthetic rows. They measure Catalog
  population/fetch and in-memory grouping, run no ImageIO decode and make no
  claim about real images, external storage or real-media hashing.

The generated fixture includes deterministic pairs separated by eight bits
across all four 16-bit blocks, which structurally exercises the large-library
index without relying on equal hashes. Cancellation is checked while resolving
roots, before/after each ImageIO hash and at bounded intervals during grouping.

## Deliberate boundaries

- No automatic deletion, source move, trash action or rating change is
  attached to similarity results. The review sheet can invoke those existing
  Library actions only after the user explicitly selects assets; Trash still
  requires confirmation.
- No cloud API, Vision feature print, face grouping or semantic search is used.
- dHash can miss heavy crops, rotation, major retouching or non-uniform edits;
  it can also produce false positives for simple repetitive graphics. Users
  must inspect displayed photos before taking any action.
- The first live-media scan necessarily reads available photo originals. Later
  scans reuse hashes only when both file size and modification time still
  match; unavailable/offline assets do not participate or retain a valid
  comparison hash. Real 10k–100k media performance, physical storage and UI
  responsiveness remain manual checks.
