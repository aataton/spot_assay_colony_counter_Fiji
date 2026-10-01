# Fiji Spot Assay Colony Counter

An interactive Fiji/ImageJ macro for counting small colonies in a rectangular spot-assay grid. It processes the **green channel of an RGB plate image**, lets you align the grid and review individual spot regions, and exports a count table and annotated contact sheet.

## What it does

The macro optionally applies CLAHE to the green channel, subtracts background, inverts the image, applies a selectable automatic threshold with an optional bias, converts to a mask, and uses watershed and Fiji's Analyze Particles command. For blobs remaining merged, it estimates colony number from blob area relative to an expected single-colony area. It places markers on detected blob centroids and labels the estimated count on a contact sheet. These are *estimates*, not confirmed identities of individual colonies.

This version is interactive, not an unattended batch processor. It supports a selectable set of grid columns, row/column position nudges, optional manual repositioning of each spot ROI, and skipping individual spots.

## Requirements and installation

- Install [Fiji](https://fiji.sc/), including its standard ImageJ commands and CLAHE plugin.
- Download `SpotAssayCounter_v06-4.ijm` from this repository. No changes to the macro are required for a basic run.
- In Fiji, open the macro with **File → Open…** and click **Run** in the editor. Alternatively, use **Plugins → Macros → Run…** and select the `.ijm` file.

## Input image and preparation

Open **one RGB plate photograph** in Fiji and ensure it is the active image before starting. The example image in this repository is `35C150uE_1.jpg`; it shows green colonies on a pale plate in a serial spot-assay layout. The macro assumes colonies are distinguishable in the **green channel**; it does not perform a blue-green hue filter or color segmentation. If the background, marker ink, or plate features have similar green-channel intensity, they may be detected too.

Use an image with the full grid visible, reasonably even lighting, minimal glare, and sufficient resolution to distinguish individual colonies. Avoid changing image scale between measuring colony size and running the macro. The source image should remain available for visual comparison with the output.

### Measure colony diameter before running

**Measure a typical isolated colony diameter in pixels before you start the macro.** This value is requested in the first settings dialog and affects both the allowed particle area and estimates for merged blobs.

1. Open a representative image in Fiji and zoom in on isolated, well-resolved colonies in the dilution range you intend to count.
2. Draw a straight line across a colony's diameter and use **Analyze → Measure** to read its length. If the image has been spatially calibrated, use the pixel distance instead of a physical-unit measurement; the macro uses pixels.
3. Repeat for several isolated colonies and enter a representative value, such as their median diameter, in **Colony diameter (px)**. If colony sizes differ markedly among images, measure each image or group of comparable images separately.

The macro sets expected single-colony area to `π × (diameter / 2)²`, the minimum accepted particle area to **0.16 ×** that area, and the maximum to **10 ×** that area. An incorrectly chosen diameter can discard real small colonies, include debris, or misestimate clusters.

## Run the macro

1. **Configure detection.** Enter the measured colony diameter. Default settings are minimum circularity `0.5`, background radius `50 px`, CLAHE off (block size `64 px`, max slope `3` if enabled), threshold method **Otsu**, threshold bias `0`, cross half-arm `5 px`, label font `14 px`, and edge expansion `8 px`.
2. **Define the grid.** On the original image, draw a rectangle around the *entire spot grid* and confirm the prompt. The rectangle defines initially uniform cell widths and heights; it is not an outline of the plate.
3. **Enter the layout.** Set the number of rows and columns and the **1-based** columns to count, comma-separated (for example, `4,5,6`). Turn on manual ROI adjustment if you want to inspect and reposition each spot. The dialog defaults (`8` rows, `8` columns, columns `3,4,5`) are examples, not settings for every plate.
4. **Align the grid.** Yellow outlines mark all cells and cyan outlines mark selected columns. Select individual rows or columns and nudge them in pixels: positive column nudge moves right; positive row nudge moves down. Repeat until aligned, then check **Done - proceed to analysis**.
5. **Review each spot, if enabled.** Drag its fixed-size box to center on the spot or check **Skip this spot**. A skipped spot is reported with `Count=0` and `Status=skipped`; it is **not** a measured zero-colony result.
6. **Choose an output folder.** Inspect the saved contact sheet against the original image, then use the CSV counts only if detection is acceptable.

## Tuning detection

| Setting | Suggested starting point | What to check |
| --- | --- | --- |
| Colony diameter | Measured diameter in pixels | Controls size filtering and merged-blob estimates; do not guess from the spot diameter. |
| Minimum circularity | `0.5` | Lower if true tiny or irregular colonies are rejected; higher if elongated debris is detected. |
| Background radius | `50 px` | Test against both broad shading and loss of colony signal. |
| CLAHE | Off initially | If faint colonies are missed, test on; the default block size is `64 px` and max slope `3`. CLAHE can also enhance noise. |
| Threshold method | `Otsu` initially | Also available: `Default`, `Moments`, `Triangle`, `Yen`, `Li`. Select by comparing masks/counts with manually checked spots. |
| Threshold bias | `0` initially | Positive values lower the lower threshold bound and may include paler features; negative values raise it and may suppress noise. Values are 8-bit intensity steps, not percentages. |
| Edge expand | About half a colony diameter | Allows particle detection near ROI borders; a particle is counted only if its centroid is inside the unexpanded spot box. |

For example, with 4–12 px colonies, measure several isolated colonies rather than entering the default `14 px`. Try Otsu with bias `0` and CLAHE off first. If faint colonies are consistently missed, compare small positive biases (such as `+2` or `+5`) and/or gentle CLAHE, while checking for new false positives. These are trial settings, not validated cutoffs for every plate.

**Important:** The macro analyzes particles in an expanded region but retains only particles whose centroids lie within the original spot box. Watershed and the area-based correction can under- or overcount densely packed spots. The contact sheet marks a remaining merged blob once, with an `xN` label when its area-based estimated count exceeds one; it does not show N separate colony centers.

## Output files

For an open image titled `plate.jpg`, the macro saves in the chosen output folder:

- `plate_colony_counts.csv` — fields `Row,Column,Count,Status`, with `ok` or `skipped` status.
- `plate_contact_sheet.tif` — annotated spot crops arranged by row and counted column, with labels and yellow centroid crosses. Skipped cells are rendered as labeled black tiles.

The actual output stem is derived from the open image title; the macro explicitly strips lowercase `.jpg`, `.png`, `.tif`, and `.tiff` endings. **Uppercase extensions such as `.JPG` are not stripped** by this version, so a file titled `35C150uE_1.JPG` may produce `35C150uE_1.JPG_colony_counts.csv` and `35C150uE_1.JPG_contact_sheet.tif`. Operating systems may append a suffix to avoid overwriting an existing output. The supplied example CSV and JPEG contact-sheet preview illustrate the output format; the macro itself saves its contact sheet as TIFF.

Example CSV rows:

```csv
Row,Column,Count,Status
1,4,0,skipped
1,5,30,ok
1,6,8,ok
```

## Quality control and limitations

- Compare annotated crops with the original plate across sparse, moderate, and crowded spots. Validate against manual counts on representative images before applying settings to a full experiment.
- Record the macro version, Fiji version, pixel diameter, threshold method and bias, background radius, CLAHE settings, circularity, grid layout, skipped spots, and any manual adjustments. Keep the original images, CSVs, and contact sheets together.
- Do not interpret confluent spots as reliably enumerated single colonies. Watershed and area-based cluster correction are heuristics, especially when colony sizes vary.
- Small, pale, irregular, merged, or partially hidden colonies can be missed; dust, scratches, ink, agar texture, bubbles, and glare can generate false positives. Low-resolution 4 px colonies are particularly sensitive to segmentation and shape filtering.
- The macro does not calculate CFU/mL, dilution-corrected titers, confidence intervals, or quality scores; perform these analyses separately after validating counts.
- Column indices must refer to existing columns. Review grid alignment and per-spot placement carefully; the macro does not validate every input or automatically recognize spots.

## Attribution and disclaimer

The repository author wrote the macro and prepared this `README.md` **with assistance from Perplexity AI**. The author remains responsible for reviewing and validating both the code and documentation. If you adapt the workflow, acknowledge the repository and report the macro version and settings used.

**Use this software at your own risk.** It is provided *as is*, without warranties or a guarantee of accuracy, fitness for a particular experiment, compatibility, or freedom from errors. Users must independently validate counts, inspect output images, safeguard original data, and decide whether results are suitable for biological interpretation, publication, or other decisions. Neither the author nor contributors accept responsibility for incorrect counts, data loss, or conclusions drawn from use of the software.

