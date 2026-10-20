# Image Edge Detection

## 1. Luminance (`lane_luma`)

### 1.1 What the module does (one sentence)
It turns a colored pixel (3 numbers: red, green, blue) into **one number that
says how bright the pixel is**.

### 1.2 Why do we need it?
Edge detection looks for places where the image changes from **dark to bright**
or from **bright to dark**. Color does not matter for that, only brightness.

If we kept all 3 colors, every later block would have to do its math 3 times.
If we first turn each pixel into one brightness number, everything after it
becomes 3 times simpler and smaller.

Example from the lane video:
- Gray asphalt: R = G = B = 150, so the brightness is about 150.
- White lane line: R = G = B = 220, so the brightness is about 220.

The jump from 150 to 220 is what the filter will later call an edge.

### 1.3 What does each pin do?

#### Inputs

| Pin | Size | What it does |
|---|---|---|
| `i_clk` | 1 bit | The clock. On every rising edge the module takes the pixel that is on `i_rgb`. |
| `i_rgb` | 24 bits | The pixel: 8 bits red + 8 bits green + 8 bits blue, all arriving at the same time. |

#### Outputs

| Pin | Size | What it does |
|---|---|---|
| `o_y` | 12 bits | The brightness of the pixel, from 0 (black) to 4080 (white). It appears **one clock after** the pixel went in. |

### 1.4 Splitting the 24 wires into R, G, B
The 24 bits are three groups of 8 bits, stacked next to each other:

```
bit 23 ........ 16 | 15 ........ 8 | 7 ........ 0
        RED        |     GREEN     |     BLUE
```

So we just give a name to each group of wires. This costs nothing in hardware,
because it only names wires that already exist:

**Why different numbers for each color?**
The human eye does not see all colors as equally bright. Green looks the
brightest, red is in the middle, and blue looks the darkest. So green gets the
biggest weight (9), red a medium one (5) and blue the smallest (2).

**Why these particular numbers?**
The real weights are about 0.30 for red, 0.59 for green and 0.11 for blue.
Multiplying by decimals is expensive in hardware, so we use whole numbers with
the same proportions: 5, 9 and 2. They add up to 16.

### 1.6 Why is the output 12 bits?
The biggest possible value happens when R, G and B are all 255 (white):

```
Y = 5×255 + 9×255 + 2×255 = 16 × 255 = 4080
```

4080 does not fit in 8 bits (maximum 255), but it fits in 12 bits (maximum
4095). So the output is 12 bits wide.

Because the weights add up to 16, `Y` is the real brightness **times 16**.
For a gray pixel (R = G = B = x), the result is simply `16 × x`:

| Pixel | Calculation | Y |
|---|---|---|
| Black (0, 0, 0) | 0 | 0 |
| Gray asphalt (150, 150, 150) | 16 × 150 | 2400 |
| White line (220, 220, 220) | 16 × 220 | 3520 |
| White (255, 255, 255) | 16 × 255 | 4080 |
| Pure red (255, 0, 0) | 5 × 255 | 1275 |



## Line Memory

### 1. What the module does (one sentence)
It stores **one row of the image** and gives it back **one row later**, so
the hardware can see the pixel that is directly above the current one.

### 2. What does each pin do?

### Inputs

| Pin | Size | What it does |
|---|---|---|
| `i_clk` | 1 bit | The clock. On every rising edge the module can take one pixel. |
| `i_rst_n` | 1 bit | Reset (active low). When it is 0, the module goes back to its start state. |
| `i_write_en` | 1 bit | "A real pixel is here right now." If 1, the module stores the pixel and moves on. If 0, it does nothing and waits. |
| `i_data_in` | 24 bits | The current pixel: 8 bits red + 8 bits green + 8 bits blue. |

### Outputs

| Pin | Size | What it does |
|---|---|---|
| `o_data` | 24 bits | The pixel that came in **one row ago** (the pixel directly above). |
| `o_valid` | 1 bit | 0 = `o_data` is still garbage, ignore it. 1 = `o_data` is real. |

### Parameters (set when you instantiate the module)

| Parameter | Meaning |
|---|---|
| `width` | Bits per pixel. 24 here. |
| `depth` | Pixels per row, which equals the image width (e.g. 1280). |

### 3. How big is the memory?
It holds **one row**: `depth` slots, each `width` bits.

```
1280 slots × 24 bits = 30,720 bits
```

The size depends on the image **width** only. The image height doesn't matter,
because only one row is stored at a time.

### 4. How the pixels arrive
The hardware receives **one pixel per clock**, row by row, left to right, top
to bottom:

```
row 0:  p0  p1  p2  ... p1279
row 1:  p0  p1  p2  ... p1279
```

Between rows there is blank time with no pixels. `i_write_en` is 0 then.

### 5. What happens inside
The memory is a **circular buffer**, and two numbers (pointers) say where to
read and write:

- `write_ptr`: the slot where the new pixel is stored.
- `read_ptr`: the slot holding the oldest pixel, which is read out.
- Both go 0, 1, 2, ... `depth-1`, then wrap back to 0.
- `read_ptr` is always one slot ahead of `write_ptr`.

On every clock where `i_write_en = 1`:
1. The old pixel at `read_ptr` is copied to `o_data`.
2. The new pixel `i_data_in` is stored at `write_ptr`.
3. Both pointers move forward by one (wrapping at `depth-1`).

A slot is read just before it is overwritten, and the pointers need exactly
`depth` steps to return to it. So the pixel that comes out went in exactly
**one row earlier**.

### 6. Why `i_write_en` matters
The pointers only move when `i_write_en = 1`. During blanking (no pixels), they
stay put, so the memory stays lined up with the image rows.

### 7. Why is the output garbage at the start?
After reset the memory is empty (X in simulation). During the first row, `o_data`
reads slots that were never written, so it is invalid and `o_valid = 0`.
After one full row has been stored, `o_valid` becomes 1 and `o_data` is real.

### 8. Reset
- Reset sets the pointers back to their start values and clears `o_valid`.
- It does **not** clear the memory contents. Clearing every slot would stop
  the tool from using block RAM and would waste thousands of flip-flops.
- Use it at start-up only. Pixels arriving during reset are lost.

### 9. Where it is used
Two line memories in series give the pixel one row above and two rows above.
Together with the current pixel, that is the 3 rows a 3×3 Sobel filter needs.

```
current pixel ──► [line mem] ──► row above ──► [line mem] ──► two rows above
```



## 3. Sobel Kernel (`sobel_kernel`)

### 3.1 What the module does (one sentence)
It takes a stream of brightness values, finds where the brightness changes
sharply (the **edges**), and outputs a gray image where edges are dark and flat
areas are white.

### 3.2 What does each pin do?

#### Inputs

| Pin | Size | What it does |
|---|---|---|
| `i_clk` | 1 bit | The clock. One pixel is processed per clock. |
| `i_rst_n` | 1 bit | Reset (active low). Resets the line memory pointers and the tap registers. |
| `i_data` | 12 bits | The brightness of the current pixel, coming from the luminance module. |
| `i_write_en` | 1 bit | "A real pixel is here right now" (data enable). It must be delayed by the same number of clocks as the luminance module, so it stays lined up with `i_data`. |

#### Outputs

| Pin | Size | What it does |
|---|---|---|
| `o_data_out` | 24 bits | The edge pixel: the same 8-bit value copied to red, green and blue. 255 (white) means no edge, close to 0 (black) means a strong edge. |

### 3.3 The big picture

```
i_data (12-bit brightness, one pixel per clock)
   │
   ▼
[1] Build a 3×3 window     2 line memories + shift registers → 9 pixels
   │
   ▼
[2] Two Sobel kernels      horizontal (Gx) and vertical (Gy), each squared
   │
   ▼
[3] Add and scale          (Gx² + Gy²) / 8192
   │
   ▼
[4] Clamp                  limit to 8191 so it fits a 13-bit address
   │
   ▼
[5] ROM (M10K)             address in → 255 − √(8 × address) out
   │
   ▼
[6] Copy to R, G, B        {lum, lum, lum} → o_data_out
```

### 3.4 Step 1: the 3×3 window
A Sobel filter looks at a pixel and its 8 neighbors, so we need 3 rows of the
image at the same time. The image arrives one pixel per clock, so we have to
remember the previous rows.

- `rb` is the current pixel (**r**ight column, **b**ottom row).
- The first line memory delays it by one row, giving the pixel above: `rc`.
- The second line memory delays that by one more row, giving `ru`.
- Three small shift registers then move each row's pixels one step to the left on
  every clock. This gives the center column (`cb`, `cc`, `cu`) and the left column
  (`lb`, `lc`, `lu`).

```
        left    center   right
up   :   lu  ←   cu   ←   ru     (two rows above)
center:  lc  ←   cc   ←   rc     (one row above)
bottom:  lb  ←   cb   ←   rb     (current row, newest pixel)
```

Pixels arrive left to right, so the newest pixel is always on the right, and
older pixels shift to the left.

The center pixel `cc` is never used by the Sobel math (both kernels have a 0
in the middle).

### 3.5 Step 2: the two kernels
Each kernel gives a number that is large when the brightness changes in one
direction.

**Horizontal gradient (Gx)** finds **vertical edges**. It subtracts the left
column from the right column:

```
-1  0  +1
-2  0  +2
-1  0  +1
```

**Vertical gradient (Gy)** finds **horizontal edges**. It subtracts the bottom row
from the top row:

```
+1  +2  +1
 0   0   0
-1  -2  -1
```

The same module (`g_matrix`) is used for both. Only the wiring changes:

| Port of `g_matrix` | Horizontal (Gx) | Vertical (Gy) |
|---|---|---|
| `i_p1a` (+1) | `ru` | `lu` |
| `i_p2` (+2) | `rc` | `cu` |
| `i_p1b` (+1) | `rb` | `ru` |
| `i_m1a` (−1) | `lu` | `lb` |
| `i_m2` (−2) | `lc` | `cb` |
| `i_m1b` (−1) | `lb` | `rb` |

`p` means plus and `m` means minus. The middle pixel gets weight 2 because it is
closer to the center.

Inside `g_matrix` (2 clocks):
1. **Sum:** `sum = p1a + 2·p2 + p1b − m1a − 2·m2 − m1b`. It can be negative, so it
   is a **signed 15-bit** number (range −16320 to +16320).
2. **Square:** `sum × sum`. Squaring removes the sign, and the result is a
   **28-bit** unsigned number (up to 266,342,400).

### 3.6 Step 3: add and scale
The true edge strength is `G = √(Gx² + Gy²)` (Pythagoras). We already have the
squares, so we add them:

```
g_total = Gx² + Gy²        (29 bits, up to 532,684,800)
g_sum   = g_total / 8192   (16 bits, up to 65,026)
```

Dividing by 8192 (2¹³) is done by taking the upper bits: `g_total[28:13]`.
It costs no hardware.

### 3.7 Step 4: clamp
The ROM address is only **13 bits**, so the largest address is **8191**. If
`g_sum` is bigger (a very strong edge), it would wrap around and turn into a
small number. To avoid this, it is **clamped**:

```systemverilog
g_limit <= (g_sum > 16'd8191) ? 13'h1FFF : g_sum[12:0];
```

Values above 8191 become 8191 (all ones), which the ROM turns into black.

### 3.8 Step 5: the ROM that takes the address (square root)
The square root is **not calculated**. It is looked up in a table.

**What it is**
- A **1-port ROM** built from Cyclone V **M10K** memory blocks (Quartus
  `altsyncram`, ROM mode, generated with the MegaWizard).
- **8192 words × 8 bits = 65,536 bits.** The wizard reports about **8 M10K**
  blocks.
- Single clock, with a registered address and a registered output, so the data
  appears **2 clocks** after the address.

**How the address is created**
The address is the clamped result of the equation above:

```
address = g_limit = min( (Gx² + Gy²) / 8192 , 8191 )
```

So the number from the Sobel equation is used directly as the **address** of the
ROM, and the ROM returns the **pre-computed answer** stored at that address.

**What is stored**
```
q = 255 − √(8 × address)
```

The ROM is filled from a `.mif` file when the FPGA is configured. Without the
`.mif`, the ROM is all zeros and every pixel would be black.

**Why 8 and 8192?**
Together they set the gain of the filter:

```
√(8 × G² / 8192) = √(G² / 1024) = G / 32
```

So the output is `255 − G/32`:
- No edge: G = 0, output 255 (white).
- The largest address, 8191, gives `√(8 × 8191) ≈ 256`, so the output goes down
  to about 0 (black). The full 8-bit range is used.

Example from the lane video: asphalt at brightness 150 and a white line at 220
is a step of 70. The gradient is about 4 × 70 = 280 (in normal brightness units),
and the output is about `255 − 280/2 = 115`, a clearly dark gray.

**Why a ROM and not a square-root circuit?**
A table lookup uses a memory block that the FPGA already has, and it needs no
logic. A real square-root circuit would need a lot of logic and several clocks.

#### 3.8.1 How the ROM gets the square root (step by step)

The idea: there are only **8192 possible addresses**, so the answer for every
one of them can be calculated **once, in advance**, and written into the memory.
At run time the hardware never calculates anything. It just reads the word at
the address.

**1. The table is calculated before the FPGA runs.**
For every address `a` from 0 to 8191 the stored word is:

```
rom[a] = 255 − floor( √(8 × a) )
```

`floor` means the decimals are cut off (rounded down). This is the same as the C
model, which does `sqrt(...)/2` and stores the result in an integer.

**2. The table is saved in `lane_g_root.mif`.**
A `.mif` (Memory Initialization File) is a text file with one line per address:

```
DEPTH = 8192;            -- number of words
WIDTH = 8;               -- bits per word
ADDRESS_RADIX = DEC;
DATA_RADIX = DEC;
CONTENT
BEGIN
  0  :  255 ;
  1  :  253 ;
  2  :  251 ;
  3  :  251 ;
  ...
  8191 :  0 ;
END;
```

**3. The ROM is filled from the file.**
`rom.v` (made by the MegaWizard) has the parameter
`init_file = "lane_g_root.mif"`. When the FPGA is configured (or when the
simulation starts) the memory is loaded with the table. After that it is
read-only.

**4. At run time the address selects one word.**
The Sobel result `g_limit` goes to the ROM address pins, and `q` shows the word
stored there, 2 clocks later:

| `g_limit` (address) | `√(8 × address)` cut to integer | `q` = 255 − that | What it means |
|---|---|---|---|
| 0 | 0 | **255** | no edge, white |
| 1 | 2 | **253** | very weak edge |
| 32 | 16 | **239** | weak edge |
| 128 | 32 | **223** | |
| 512 | 64 | **191** | medium edge |
| 2048 | 128 | **127** | strong edge, middle gray |
| 4096 | 181 | **74** | |
| 8191 | 255 | **0** | strongest edge (also every clamped value), black |

**5. Why this gives the correct edge strength.**
`g_limit` is `(Gx² + Gy²) / 8192`. The ROM then takes the root of 8 times that:

```
√( 8 × (Gx² + Gy²) / 8192 ) = √( (Gx² + Gy²) / 1024 ) = √(Gx² + Gy²) / 32
```

So the ROM output is `255 − G/32`, where `G = √(Gx² + Gy²)` is the real Sobel
edge strength. The squares were needed first, because `Gx` and `Gy` are added
**before** the root, as in Pythagoras. The ROM does the root, the `/8192` and the
factor 8 are chosen so that the strongest edge lands exactly on address 8191 and
the answer on 0.

**6. The table is small and has a limit.**
Because the address is only 13 bits, nearby values of `Gx² + Gy²` share one
address (the lowest 13 bits of the division are dropped). The answer is
therefore a bit coarse, but the C model (`lane_fixed.c`, `lane_testbench.c`)
does exactly the same quantization (`g_limit_13bit = 32*(g_limit/32)`), so the
hardware matches it bit for bit.

**If you ever need to rebuild the `.mif`** (for example, it is lost), this
script produces it:

```python
import math
with open("lane_g_root.mif", "w") as f:
    f.write("DEPTH = 8192;\nWIDTH = 8;\nADDRESS_RADIX = DEC;\nDATA_RADIX = DEC;\n")
    f.write("CONTENT\nBEGIN\n")
    for a in range(8192):
        f.write(f"{a} : {255 - math.isqrt(8 * a)} ;\n")
    f.write("END;\n")
```



### 3.9 Step 6: copy to R, G and B
```systemverilog
assign o_data_out = {lum, lum, lum};
```
The video output needs a 24-bit RGB pixel. Using the same 8 bits for red,
green and blue gives a **gray** pixel.

### 3.10 Pipeline delay
Every register adds one clock of delay. Pixels and control signals (`vs`, `hs`,
`de`) must be delayed by the same amount.

| Stage | Clocks |
|---|---|
| `g_matrix` (sum, square) | 2 |
| `g_sum` (add and divide) | 1 |
| `g_limit` (clamp) | 1 |
| ROM (address register + output register) | 2 |
| **Inside `sobel_kernel`** | **6** |
| Luminance module (before it) | 1 |
| **From `i_rgb` to `o_data_out`** | **7** |

The sync signals therefore need a delay of **7 clocks**, as in the original design.

### 3.11 Things to know
- **Borders:** the first two rows and the first two columns of the output are
  not valid (the 3×3 window is not full yet). Ignore or blank them.
- **Resolution:** the output has the same size as the input. Nothing is cropped.
- **Reset:** the line memories are not cleared (that would stop block RAM from
  being used). Use reset at start-up only.
- **Enable:** `i_write_en` must be delayed by the same clocks as the data in
  front of this module (1 clock for the luminance module).
- **Signed vs unsigned:** `sum` inside `g_matrix` is signed. Everything else is
  unsigned.
- **Rounding:** the ROM table rounds the square root **down** (cuts the
  decimals), like the C model. If the output differs from the expected image by
  1 in some pixels, check that the `.mif` was not built with rounding to the
  nearest integer.


## 4. Running the SystemVerilog simulation (and making sure the ROM is read)

The ROM is the one part of the design that is not plain SystemVerilog. It uses
Altera's `altsyncram` memory model and loads a separate file (`lane_g_root.mif`).
If either of these is missing, the simulation still starts but the output is
wrong. This section shows how to set it up so the ROM really contains the table.

### 4.1 Files you need

| File | Purpose |
|---|---|
| `top_edge_detect.sv` (module `lane`), `lane_luma.sv`, `lane_sync.sv`, `line_mem.sv`, `g_matrix.sv`, `sobel_kernel.sv` | the design |
| `rom.v` | the ROM wrapper made by the MegaWizard |
| `altera_mf.v` | Altera's simulation model of `altsyncram` (about 31,000 lines, from `<quartus>/eda/sim_lib/`) |
| `lane_g_root.mif` | the table that fills the ROM |
| `sim_lane.vhd` | the testbench (VHDL), protocol described in section 5 |
| `street_A_stimuli.txt`, `street_A_expected.txt` | input image and correct answer, made by `lane_testbench` |

Do **not** add `rom_bb.v` to the simulation. It is an empty black box for Quartus.
If it is compiled after `rom.v`, it replaces the real ROM and `q` stays `Z`
(undriven).

`altera_lnsim.sv` is not the right model. `altsyncram` is in `altera_mf.v`.

### 4.2 Set up the folder

ModelSim reads the `.mif` and the `.txt` files from the **working directory** of
the simulation. This is the folder of the ModelSim project (the one that contains
the `.mpf` file), not the folder of the source files.

1. Copy `lane_g_root.mif`, `street_A_stimuli.txt` and `street_A_expected.txt`
   into the ModelSim project folder.
2. In the ModelSim transcript type `pwd` to check that this is the working
   directory.
3. Make sure the file names inside `sim_lane.vhd` match your files
   (`street_A_stimuli.txt`, and so on).

### 4.3 Compile

Compile all design files and `altera_mf.v`, then `sim_lane.vhd` last:

```
vlog -sv g_matrix.sv lane_luma.sv lane_sync.sv line_mem.sv sobel_kernel.sv top_edge_detect.sv
vlog rom.v altera_mf.v
vcom sim_lane.vhd
```

All compiles must finish with `0 failed`. (In the GUI: Compile > Compile All.)

### 4.4 Start the simulation

```
vsim work.sim_lane
```

If `altsyncram` is compiled into another library (for example `altera_mf_ver`),
start it with `vsim -L altera_mf_ver work.sim_lane`.

The ROM is loaded **at time 0**, when `vsim` starts. If you copy or change the
`.mif` later, you must restart the simulation (`restart -f`, or End Simulation and
`vsim` again). Changing it while the simulation is open has no effect.

### 4.5 Check that the ROM is read

Do these checks before running the whole frame (about 10 ms of simulation, which
takes a few minutes):

1. **Look at the transcript after `vsim`.** The lines
   `Loading work.altsyncram`, `Loading work.altsyncram_body` and
   `Loading work.ALTERA_MF_MEMORY_INITIALIZATION` show that the memory model and
   its file loader were found. There must be no warning that mentions
   `lane_g_root.mif`.
2. **Probe the ROM output.**
   ```
   add wave -r /sim_lane/duv/u_sobel/rom_1/*
   run 20 us
   ```
   `q` must show real values (for example `FF` for an address of 0), not `Z`
   and not a stuck `00`.
3. **Optional: look inside the memory.** Open the *Memory List* tab, double-click
   the `altsyncram` memory of `rom_1`, and compare the first words with the table
   in 3.8.1 (`0 → 255`, `1 → 253`, `2 → 251`, `3 → 251`).

### 4.6 Run the whole frame

```
run -all
```

Do not press Break. The response file `street_A_response.txt` is complete only
when the run finishes. The run ends with a message from the testbench (shown as a
"Failure", which is how the testbench stops on purpose):

- `Simulation completed, EVERYTHING OK` means every pixel matches the C model.
- `Simulation completed, N MISMATCHES` means N pixels differ. Each one is printed
  as `MISMATCH in simulation at position x=... y=...`.

Convert the result to an image with `sim2bmp street_A_response` and compare it
with `street_A_edge_fixed.bmp`.

### 4.7 What a wrong ROM looks like

Open `street_A_response.txt` and look at the lines after the first two rows
(the first valid pixel is line 2564, x = 2, y = 2):

| What the response shows | Cause | Fix |
|---|---|---|
| `ZZ ZZ ZZ` in every valid pixel | The ROM output is undriven: `rom_bb.v` was compiled, or `altsyncram` was not found | Remove `rom_bb.v`, compile `altera_mf.v`, recompile all |
| Error `vsim-3033 ... 'altsyncram' failed. The design unit was not found` | `altera_mf.v` is not compiled or not in the search path | Compile `altera_mf.v` (or use `-L altera_mf_ver`) |
| `00 00 00` in every valid pixel | The ROM is empty: the `.mif` was not found | Put `lane_g_root.mif` in the working directory and restart the simulation |
| Values are real but a few differ by 1 | The `.mif` was built with a different rounding | Rebuild it with the script in 3.8.1 |
| Values are real but shifted by one or more pixels | Pipeline delay is not 7 clocks | Check the delay of `lane_sync` against section 3.10 |


## 5. Writing your own testbench (how pixels enter and leave the design)

This section describes the interface of the top module `lane` and the exact
protocol that `sim_lane.vhd` uses. If you follow the same protocol, any new
testbench will work with the design.

### 5.1 How the design receives pixels from the upper layer

The design has **no memory interface and no handshake**. The upper layer (the
video source on the board, or the testbench in simulation) pushes the image in
as a **video stream**: one pixel per clock, row by row, left to right, top to
bottom. The design cannot ask the source to wait, so the source must deliver
every pixel on time.

Three control signals tell the design what is on the pixel wires:

| Signal | Meaning |
|---|---|
| `de_in` (data enable) | 1 = `r_in`, `g_in`, `b_in` hold a **real pixel** right now. 0 = blanking, ignore the colour wires. This is the "a real pixel is here" flag that the line memory and the Sobel kernel use as `i_write_en` (delayed to match the luminance module, see 3.2). |
| `hs_in` (horizontal sync) | 1 during the blanking time **before** the pixels of every row. |
| `vs_in` (vertical sync) | 1 during the **first row** of every frame. It marks the start of a new image. |

### 5.2 Ports of `lane`

#### Inputs

| Pin | Size | What the testbench does with it |
|---|---|---|
| `clk` | 1 bit | Clock, period 10 ns (100 MHz). The design samples all inputs on the **rising** edge. |
| `reset_n` | 1 bit | Reset, active low (see 5.3). |
| `enable_in` | 3 bits | Held at `"111"` for the whole run. |
| `vs_in` | 1 bit | Vertical sync (see 5.1). |
| `hs_in` | 1 bit | Horizontal sync (see 5.1). |
| `de_in` | 1 bit | Data enable (see 5.1). |
| `r_in`, `g_in`, `b_in` | 8 bits each | The pixel colour. Together they are `i_rgb` of the luminance module (`{r, g, b}`, 24 bits). |

#### Outputs

| Pin | Size | What it does |
|---|---|---|
| `vs_out`, `hs_out`, `de_out` | 1 bit each | The same three signals as the inputs, delayed by **7 clocks** (see 3.10), so they stay lined up with the output pixel. |
| `r_out`, `g_out`, `b_out` | 8 bits each | The edge pixel. All three are equal (gray, see 3.9). Only valid when `de_out = 1`. |
| `clk_o`, `led` | 1 bit, 3 bits | Connected in the testbench but **not checked**. |

### 5.3 Reset

- `reset_n` is **0 from time 0 until 50 ns**, then goes to 1. With a 10 ns
  clock this is **5 rising clock edges** (at 5, 15, 25, 35 and 45 ns).
- During reset all inputs are 0 (`vs_in`, `hs_in`, `de_in` and the colour wires),
  so no pixel is sent.
- After reset is released the testbench waits until **100 ns** (another 5
  clocks) before the first row starts. So the first pixel only arrives when the
  design has been out of reset for some time.
- Reset is applied **once, at the start**, and never again during a frame.
  Pixels that arrive during reset are lost, and the line memories are not
  cleared (see "Reset" in the Line Memory section and 3.11).

### 5.4 Timing of one frame

Every row has a blanking part and an active part:

```
             |<-- x_blank = 100 clocks -->|<----- x_size = 1280 clocks ----->|
hs_in    ____/``````````````````````````\_____________________________________/``` (next row)
de_in    ____________________________________/```````````````````````````````\____
r/g/b    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 p0  p1  p2  ...  p1278  p1279  0 0 0
```

| Part | Length | `hs_in` | `de_in` | `r_in`, `g_in`, `b_in` |
|---|---|---|---|---|
| Blanking | 100 clocks | 1 | 0 | 0 |
| Active pixels | 1280 clocks | 0 | 1 | one pixel per clock |

Other rules:

- `vs_in` is 1 during the **whole first row** (blanking and active part) and 0
  for all other rows.
- One row takes 100 + 1280 = **1380 clocks**. One frame of 720 rows takes
  720 × 1380 = **993,600 clocks**, which is about **9.94 ms** at 10 ns.
- The testbench changes its inputs on the **falling** clock edge. Every pixel
  stays on the wires for exactly one clock and is taken by the design on the
  next rising edge. This avoids a race between the clock and the data.
- The 1280 active pixels of a row follow each other **without gaps**
  (`de_in` stays 1 for the whole row). Gaps inside a row are not tested.
- After the last row, `de_in` and `hs_in` stay 0 and the testbench runs for
  **1000 more clocks** (`trail`), so that the last pixels (7 clocks of
  pipeline delay) can leave the design before the simulation stops.

### 5.5 The testbench constants

These constants are at the top of `sim_lane.vhd`:

| Constant | Value | Meaning |
|---|---|---|
| `stimuli_filename` | `street_0_stimuli.txt` | Input image. |
| `expected_filename` | `street_0_expected.txt` | Correct answer from the C model. |
| `response_filename` | `street_0_response.txt` | Written by the testbench. |
| `x_size` | 1280 | Pixels per row. |
| `y_size` | 720 | Rows per frame. |
| `x_blank` | 100 | Clocks of horizontal blanking before every row. |
| `trail` | 1000 | Clocks to run after the last row. |

If you use a different image size, change `x_size` and `y_size` **and** the
`depth` parameter of the line memory (it must equal the image width, see the
Line Memory section).

### 5.6 The text file format

The stimuli, expected and response files all use the same format:

```
# comment line (skipped by the testbench)
FF A0 12
...
```

- The first line is a comment.
- Then **one line per pixel**: red, green and blue as 2-digit hex numbers,
  separated by spaces.
- The order is row by row, left to right, top to bottom, so a 1280 × 720 image
  has 921,600 pixel lines.

### 5.7 How the testbench reads the output

- It waits for the **first `hs_out = 1`**, then looks at the output on every
  falling clock edge.
- Whenever `de_out = 1`, that is one output pixel. The testbench counts the
  pixels itself (`x_pos` from 0 to 1279, then `y_pos` goes up by one). It does
  **not** use `vs_out` or `hs_out` after the start, so the design must produce
  exactly 1280 `de_out` pixels per row, in order.
- For `x_pos < 2` or `y_pos < 2` (the invalid border, see 3.11), the testbench
  writes white (`FF FF FF`) to the response file and does **not** compare.
  The expected file still has a line for these pixels, which is read and
  ignored.
- For all other pixels, `r_out`, `g_out`, `b_out` are compared with the
  expected line. Every difference increases `mismatch` and prints
  `MISMATCH in simulation at position x=... y=...`.
- The testbench ends on purpose with `severity failure` (see 4.6), which
  prints either `EVERYTHING OK` or the number of mismatches.

### 5.8 Checklist for a new testbench

1. Instantiate `lane` and connect all ports (`clk_o` and `led` can be left
   unused). Use a clock with a 10 ns period.
2. Set `enable_in` to `"111"` and all other inputs to 0.
3. Hold `reset_n` at 0 for at least 5 clocks, then release it.
4. Wait a few clocks after reset (the supplied testbench waits until 100 ns).
5. For every row: `hs_in = 1` for 100 clocks with `de_in = 0`; then `hs_in = 0`,
   `de_in = 1`, and one pixel per clock for 1280 clocks; then `de_in = 0` and
   the colour wires back to 0. Set `vs_in = 1` in the first row only.
6. Change the inputs on the falling clock edge.
7. After the last row, wait at least 7 clocks (the pipeline delay) before you
   stop. The supplied testbench waits 1000.
8. Capture `r_out`, `g_out`, `b_out` on every clock where `de_out = 1`, and
   ignore the first two columns and the first two rows.