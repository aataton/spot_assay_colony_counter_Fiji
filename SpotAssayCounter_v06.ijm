// ============================================================
// Spot Assay Colony Counter v06
// - Optional CLAHE contrast enhancement
// - Configurable threshold method and bias for pale colonies
// - Skip checkbox merged into waitForUser step (single dialog)
// - Grid adjustment dialog uses plain ASCII separators (no wide chars)
// - setBatchMode for speed during processing
// ============================================================

// Force full memory cleanup before starting
run("Collect Garbage");   // triggers Java garbage collection
call("java.lang.System.gc");  // forces a second GC pass
wait(500);                // give JVM 500ms to finish releasing
print("Memory before run: " + IJ.freeMemory());

// ============================================================
// SETTINGS DIALOG
// All key parameters in one place with explanations
// ============================================================
Dialog.create("Spot Assay Counter - Settings");

Dialog.addMessage("--- COLONY DETECTION ---");
Dialog.addNumber("Colony diameter (px):", 14);
// Measure a typical isolated colony in Fiji (Analyze > Measure)
// and enter its diameter here. Drives area estimation and cross size.

Dialog.addNumber("Min circularity (0=any, 1=perfect circle):", 0.5);
// Filters out non-circular debris. Lower if colonies are irregular.
// Raise (e.g. 0.7) to be stricter and exclude elongated artifacts.

Dialog.addMessage("--- BACKGROUND SUBTRACTION ---");
Dialog.addNumber("Background radius (px):", 50);
// Rolling ball radius for Subtract Background.
// Should be larger than the largest colony but smaller than the spot.
// Increase if background is uneven; decrease if colonies are large.

Dialog.addMessage("--- CONTRAST / THRESHOLD (optional) ---");
Dialog.addCheckbox("Enable local contrast enhancement (CLAHE)", false);
// When enabled, runs Enhance Local Contrast (CLAHE) on the green channel
// before background subtraction. Helps reveal pale colonies.
Dialog.addNumber("CLAHE block size (px):", 64);
// Typical: 32–128, depends on colony spacing
Dialog.addNumber("CLAHE max slope (0–10):", 3.0);
// Typical: 2–4; higher = stronger local contrast

Dialog.addChoice("Threshold method:",
    newArray("Otsu", "Default", "Moments", "Triangle", "Yen", "Li"), "Otsu");
// Otsu matches original behavior; others optional.

Dialog.addNumber("Threshold bias (8-bit, + = more sensitive):", 0);
// Positive values lower the threshold, including paler colonies.

Dialog.addMessage("--- DISPLAY ---");
Dialog.addNumber("Cross marker size (px half-arm):", 5);
// Half-length of the yellow cross drawn at each colony centroid.
// Keep smaller than colony radius so it does not obscure the colony.

Dialog.addNumber("Label font size (px):", 14);
// Size of the R/C count label drawn in the top-left of each cell.

Dialog.addMessage("--- EDGE HANDLING ---");
Dialog.addNumber("Edge expand (px):", 8);
// How many pixels the detection ROI is expanded beyond the cell border.
// Captures colonies whose centre sits near or on the cell edge.
// Set to ~half the colony diameter (default = colony radius).

Dialog.show();

// Read values
COLONY_DIAMETER  = Dialog.getNumber();
MIN_CIRCULARITY  = Dialog.getNumber();
BG_RADIUS        = Dialog.getNumber();
ENHANCE_CLAHE    = Dialog.getCheckbox();
CLAHE_BLOCK      = Dialog.getNumber();
CLAHE_SLOPE      = Dialog.getNumber();
THRESH_METHOD    = Dialog.getChoice();
THRESH_BIAS      = Dialog.getNumber();
CROSS_SIZE       = Dialog.getNumber();
FONT_SIZE        = Dialog.getNumber();
EDGE_EXPAND      = Dialog.getNumber();

// Derived — always recalculated from diameter, never set manually
SINGLE_COLONY_AREA = PI * pow(COLONY_DIAMETER / 2, 2);

print("Settings:");
print("  Colony diameter:     " + COLONY_DIAMETER + " px");
print("  Single colony area:  " + SINGLE_COLONY_AREA + " px2");
print("  Min circularity:     " + MIN_CIRCULARITY);
print("  Background radius:   " + BG_RADIUS + " px");
print("  CLAHE enabled:       " + ENHANCE_CLAHE);
print("  CLAHE block size:    " + CLAHE_BLOCK + " px");
print("  CLAHE max slope:     " + CLAHE_SLOPE);
print("  Threshold method:    " + THRESH_METHOD);
print("  Threshold bias:      " + THRESH_BIAS + " (8-bit)");
print("  Cross size:          " + CROSS_SIZE + " px");
print("  Font size:           " + FONT_SIZE + " px");
print("  Edge expand:         " + EDGE_EXPAND + " px");

// ============================================================
// IMAGE AND TITLE SETUP
// ============================================================
if (isOpen("for_thresh")) {
    selectWindow("for_thresh");
    close();
}

id_current = getImageID();
if (id_current == -1) exit("No image open.");

selectImage(id_current);
title = getTitle();
id_original = getImageID();

title_clean = title;
if (endsWith(title_clean, ".tif"))  title_clean = replace(title_clean, ".tif",  "");
if (endsWith(title_clean, ".tiff")) title_clean = replace(title_clean, ".tiff", "");
if (endsWith(title_clean, ".jpg"))  title_clean = replace(title_clean, ".jpg",  "");
if (endsWith(title_clean, ".png"))  title_clean = replace(title_clean, ".png",  "");

// ============================================================
// STEP 1 — Draw rectangle to define grid bounds
// ============================================================
setBatchMode(false);
selectImage(id_original);
setTool("rectangle");
waitForUser("Define Grid",
    "Draw a rectangle around the ENTIRE spot grid,\n" +
    "then click OK.");
getSelectionBounds(x_start, y_start, grid_w, grid_h);
run("Select None");

// ============================================================
// STEP 2 — Grid layout dialog
// ============================================================
Dialog.create("Grid Layout");
Dialog.addNumber("Number of rows:",    8);
Dialog.addNumber("Number of columns:", 8);
Dialog.addString("Columns to count (comma-separated):", "3,4,5");
Dialog.addCheckbox("Enable manual ROI adjustment per spot?", true);
Dialog.show();

n_rows        = Dialog.getNumber();
n_cols        = Dialog.getNumber();
cols_str      = Dialog.getString();
manual_adjust = Dialog.getCheckbox();

count_cols   = split(cols_str, ",");
n_count_cols = count_cols.length;

cell_w = grid_w / n_cols;
cell_h = grid_h / n_rows;
print("Uniform cell size: " + cell_w + " x " + cell_h + " px");

col_x = newArray(n_cols);
row_y = newArray(n_rows);
col_i = 0;
while (col_i < n_cols) { col_x[col_i] = x_start + col_i * cell_w; col_i++; }
row_i = 0;
while (row_i < n_rows) { row_y[row_i] = y_start + row_i * cell_h; row_i++; }

// ============================================================
// STEP 3 — Interactive grid adjustment
// Plain ASCII labels — no wide/special characters
// ============================================================
function drawGrid() {
    selectImage(id_original);
    run("Remove Overlay");
    ri = 0;
    while (ri < n_rows) {
        ci2 = 0;
        while (ci2 < n_cols) {
            makeRectangle(col_x[ci2], row_y[ri], cell_w, cell_h);
            run("Add Selection...", "stroke=yellow width=1");
            ci2++;
        }
        ri++;
    }
    ci2 = 0;
    while (ci2 < n_count_cols) {
        co = parseInt(count_cols[ci2]) - 1;
        ri = 0;
        while (ri < n_rows) {
            makeRectangle(col_x[co], row_y[ri], cell_w, cell_h);
            run("Add Selection...", "stroke=cyan width=2");
            ri++;
        }
        ci2++;
    }
    run("Select None");
}

drawGrid();

keep_adjusting = true;
while (keep_adjusting) {

    Dialog.create("Adjust Grid");
    // Plain ASCII only — avoids wide dialog caused by special chars
    Dialog.addMessage("Select columns and/or rows to shift, enter nudge, click OK.");
    Dialog.addMessage("Yellow = all cells | Cyan = counted columns");
    Dialog.addMessage("------- COLUMNS (shift left/right) -------");
    col_i = 0;
    while (col_i < n_cols) {
        Dialog.addCheckbox("Col " + col_i + " x=" + col_x[col_i], false);
        col_i++;
    }
    Dialog.addNumber("Column nudge px (+right / -left):", 0);
    Dialog.addMessage("------- ROWS (shift up/down) -------");
    row_i = 0;
    while (row_i < n_rows) {
        Dialog.addCheckbox("Row " + row_i + " y=" + row_y[row_i], false);
        row_i++;
    }
    Dialog.addNumber("Row nudge px (+down / -up):", 0);
    Dialog.addMessage(" ");
    Dialog.addCheckbox("Done - proceed to analysis", false);
    Dialog.show();

    // Read in exact add order
    col_selected = newArray(n_cols);
    col_i = 0;
    while (col_i < n_cols) {
        col_selected[col_i] = Dialog.getCheckbox();
        col_i++;
    }
    col_nudge = Dialog.getNumber();

    row_selected = newArray(n_rows);
    row_i = 0;
    while (row_i < n_rows) {
        row_selected[row_i] = Dialog.getCheckbox();
        row_i++;
    }
    row_nudge = Dialog.getNumber();

    done = Dialog.getCheckbox();

    if (done) {
        keep_adjusting = false;
    } else {
        col_i = 0;
        while (col_i < n_cols) {
            if (col_selected[col_i] == true)
                col_x[col_i] = col_x[col_i] + col_nudge;
            col_i++;
        }
        row_i = 0;
        while (row_i < n_rows) {
            if (row_selected[row_i] == true)
                row_y[row_i] = row_y[row_i] + row_nudge;
            row_i++;
        }
        drawGrid();
    }
}
run("Remove Overlay");

// ============================================================
// STEP 4 — Build thresholded image (batch = fast)
// ============================================================
setBatchMode(true);
selectImage(id_original);
run("Duplicate...", "title=for_thresh");
run("Split Channels");
selectWindow("for_thresh (red)");  close();
selectWindow("for_thresh (blue)"); close();
selectWindow("for_thresh (green)");
id_green = getImageID();

// Ensure 8-bit before further processing
run("8-bit");

// Optional local contrast enhancement (CLAHE) to reveal pale colonies
if (ENHANCE_CLAHE) {
    // Enhance Local Contrast (CLAHE): blocksize, histogram=256, maximum slope
    run("Enhance Local Contrast (CLAHE)",
        "blocksize=" + CLAHE_BLOCK +
        " histogram=256 maximum=" + CLAHE_SLOPE + " mask=*None*");
}

// Background subtraction and inversion
run("Subtract Background...", "rolling=" + BG_RADIUS + " light");
run("Invert");

// Auto-threshold using selected method; "dark" = colonies darker than background
setAutoThreshold(THRESH_METHOD + " dark");

// Optional threshold bias: positive = more sensitive (includes paler colonies)
// implemented as lowering the lower threshold bound before binarization
if (THRESH_BIAS != 0) {
    getThreshold(lower, upper);
    newLower = lower - THRESH_BIAS;
    if (newLower < 0) newLower = 0;
    setThreshold(newLower, upper);
}

// Force pixel units, binarize, and split touching colonies
run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
run("Convert to Mask");
run("Watershed");

setBatchMode(false);

// ============================================================
// STEP 5 — Output folder
// ============================================================
output_dir = getDirectory("Choose output folder");

crop_titles = newArray(n_rows * n_count_cols);
counts      = newArray(n_rows * n_count_cols);
idx = 0;

run("Clear Results");
roiManager("reset");
selectImage(id_original);
setTool("rectangle");

min_area = SINGLE_COLONY_AREA * 0.16;
max_area = SINGLE_COLONY_AREA * 10;

// ============================================================
// STEP 6 — Main analysis loop
// ============================================================
row_loop = 0;
while (row_loop < n_rows) {
    ci_loop = 0;
    while (ci_loop < n_count_cols) {
        c = parseInt(count_cols[ci_loop]) - 1;

        x1 = col_x[c];
        y1 = row_y[row_loop];
        w1 = cell_w;
        h1 = cell_h;

        // ---- Optional per-spot manual adjustment ----
        if (manual_adjust) {
            setBatchMode(false);
            selectImage(id_original);
            makeRectangle(x1, y1, w1, h1);

            // Single non-blocking dialog: image stays interactive
            // so user can drag the rectangle, AND skip checkbox is here
            Dialog.createNonBlocking("R"+(row_loop+1)+" C"+(c+1));
            Dialog.addMessage(
                "Row " + (row_loop+1) + "  |  Column " + (c+1) + "\n" +
                "Drag the yellow box to centre on the spot.\n" +
                "Fixed size: " + w1 + " x " + h1 + " px");
            Dialog.addCheckbox("Skip this spot", false);
            Dialog.show();

            skip = Dialog.getCheckbox();

            if (skip) {
                setBatchMode(true);
                counts[idx] = -1;
                crop_name   = "crop_R"+(row_loop+1)+"_C"+(c+1);
                crop_titles[idx] = crop_name;
                newImage(crop_name, "RGB black", w1, h1, 1);
                setFont("SansSerif", FONT_SIZE, "bold");
                setColor(180, 180, 180);
                drawString("R"+(row_loop+1)+" C"+(c+1)+": skipped",
                           4, FONT_SIZE+2);
                idx++;
                ci_loop++;
                continue;
            }

            // Read adjusted position only (size stays fixed)
            selectImage(id_original);
            getSelectionBounds(adj_x, adj_y, adj_w, adj_h);
            x1 = adj_x;
            y1 = adj_y;
        }

        // ---- Processing in batch mode ----
        setBatchMode(true);

        img_w  = getWidth();
        img_h  = getHeight();
        x1_exp = maxOf(0,     x1 - EDGE_EXPAND);
        y1_exp = maxOf(0,     y1 - EDGE_EXPAND);
        x2_exp = minOf(img_w, x1 + w1 + EDGE_EXPAND);
        y2_exp = minOf(img_h, y1 + h1 + EDGE_EXPAND);

        selectImage(id_green);
        makeRectangle(x1_exp, y1_exp, x2_exp - x1_exp, y2_exp - y1_exp);
        run("Clear Results");
        run("Analyze Particles...",
            "size=" + min_area + "-" + max_area +
            " circularity=" + MIN_CIRCULARITY + "-1.00" +
            " show=Nothing display clear");

        n_particles  = nResults;
        colony_count = 0;
        max_blobs    = n_particles + 1;
        blob_cx      = newArray(max_blobs);
        blob_cy      = newArray(max_blobs);
        blob_n       = newArray(max_blobs);
        n_blobs      = 0;

        part_i = 0;
        while (part_i < n_particles) {
            cx_abs = getResult("X", part_i);
            cy_abs = getResult("Y", part_i);

            if (cx_abs >= x1 && cx_abs < x1 + w1 &&
                cy_abs >= y1 && cy_abs < y1 + h1) {

                particle_area = getResult("Area", part_i);
                ratio = particle_area / SINGLE_COLONY_AREA;

                // Watershed already split most touching colonies correctly.
                // Area estimation only kicks in for blobs Watershed could NOT split
                // (those remaining above 1.5x single colony size).
                if      (ratio < 1.25)  n_est = 1;   // Watershed did its job
                else if (ratio < 2.0)  n_est = 2;   // Watershed missed a pair
                else if (ratio < 2.5)  n_est = 3;
                else if (ratio < 4.2)  n_est = 4;
                else if (ratio < 5.2)  n_est = 5;
                else if (ratio < 6.2)  n_est = 6;
                else if (ratio < 7.2)  n_est = 7;
                else if (ratio < 8.2)  n_est = 8;
                else if (ratio < 9.2)  n_est = 9;
                else                   n_est = 10;

                colony_count        += n_est;
                blob_cx[n_blobs]     = cx_abs - x1;
                blob_cy[n_blobs]     = cy_abs - y1;
                blob_n[n_blobs]      = n_est;
                n_blobs++;
            }
            part_i++;
        }

        counts[idx] = colony_count;
        print("R" + (row_loop+1) + " C" + (c+1) + ": " + colony_count);

        selectImage(id_original);
        makeRectangle(x1, y1, w1, h1);
        crop_name = "crop_R" + (row_loop+1) + "_C" + (c+1);
        run("Duplicate...", "title=" + crop_name);
        crop_titles[idx] = crop_name;

        blob_i = 0;
        while (blob_i < n_blobs) {
            cx    = blob_cx[blob_i];
            cy    = blob_cy[blob_i];
            n_est = blob_n[blob_i];
            setColor(0, 0, 0);
            drawLine(cx - CROSS_SIZE + 1, cy + 1, cx + CROSS_SIZE + 1, cy + 1);
            drawLine(cx + 1, cy - CROSS_SIZE + 1, cx + 1, cy + CROSS_SIZE + 1);
            setColor(255, 220, 0);
            drawLine(cx - CROSS_SIZE, cy, cx + CROSS_SIZE, cy);
            drawLine(cx, cy - CROSS_SIZE, cx, cy + CROSS_SIZE);
            if (n_est > 1) {
                setFont("SansSerif", 10, "bold");
                setColor(0, 0, 0);
                drawString("x" + n_est, cx + CROSS_SIZE + 2, cy + 4);
                setColor(255, 220, 0);
                drawString("x" + n_est, cx + CROSS_SIZE + 1, cy + 3);
            }
            blob_i++;
        }

        label = "R"+(row_loop+1)+" C"+(c+1)+": "+colony_count;
        setFont("SansSerif", FONT_SIZE, "bold");
        setColor(0, 0, 0);
        drawString(label, 3, FONT_SIZE + 3);
        setColor(255, 255, 255);
        drawString(label, 2, FONT_SIZE + 2);

        idx++;
        ci_loop++;
    }
    row_loop++;
}

// ============================================================
// STEP 7 — Assemble contact sheet
// ============================================================
setBatchMode(true);
idx2 = 0;
while (idx2 < crop_titles.length) {
    selectWindow(crop_titles[idx2]);
    idx2++;
}
run("Images to Stack", "name=CropStack title=crop_ use");
id_stack = getImageID();

run("Make Montage...",
    "columns=" + n_count_cols + " rows=" + n_rows +
    " scale=1 border=3 font=12");
// Make Montage may have already closed the stack — capture montage ID now
id_montage = getImageID();

setBatchMode(false);
sheet_path = output_dir + title_clean + "_contact_sheet.tif";
saveAs("Tiff", sheet_path);
print("Contact sheet saved: " + sheet_path);

// Close montage by ID (title changed after saveAs)
selectImage(id_montage); close();

// Close stack only if Make Montage did not already consume it
if (isOpen(id_stack)) {
    selectImage(id_stack); close();
}

// ============================================================
// STEP 8 — Save CSV
// ============================================================
csv_path = output_dir + title_clean + "_colony_counts.csv";
f = File.open(csv_path);
print(f, "Row,Column,Count,Status");
idx2 = 0;
while (idx2 < n_rows * n_count_cols) {
    ri2 = floor(idx2 / n_count_cols);
    ci2 = idx2 - ri2 * n_count_cols;
    if (counts[idx2] == -1) {
        status    = "skipped";
        count_val = 0;
    } else {
        status    = "ok";
        count_val = counts[idx2];
    }
    print(f, (ri2+1)+","+parseInt(count_cols[ci2])+","+count_val+","+status);
    idx2++;
}
File.close(f);
print("CSV saved: " + csv_path);

// ---- Clean up ----
if (isOpen(id_green)) { selectImage(id_green); close(); }
print("All done!");

// Release all intermediate images explicitly
run("Collect Garbage");
call("java.lang.System.gc");
print("Memory after run: " + IJ.freeMemory());