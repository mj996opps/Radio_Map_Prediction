# Radio Map Prediction Data Generation

This repository contains the MATLAB data-generation code used for the
simulation dataset in the paper:

**Model-Aided Learning for Sparse Received Signal Strength Indicator Radio Map
Prediction and Wireless Signal Management in Internet of Things Environments**

The repository includes all codes for data generation.

## Contents

```text
Radio_Map_Prediction/
  README.md
  LICENSE
  .gitignore
  matlab/
    generate_ble_radio_map_dataset.m
```

## MATLAB Script

The main script is:

```text
matlab/generate_ble_radio_map_dataset.m
```

It generates multi-band IoT-style indoor RSSI radio-map samples with:

- synthetic indoor wall and obstacle layouts
- wall-loss maps
- transmitter/anchor locations
- dense RSSI radio maps
- sparse RSSI measurement masks
- model-aided propagation-prior channels
- metadata and preview figures

The script is self-contained: helper functions for layout generation,
wall-loss accumulation, sparse sampling, feature construction, preview plotting,
and dataset README writing are included in the same `.m` file.

## Default Dataset Configuration

The default configuration generates:

- grid size: `96 x 96`
- cell size: `0.25 m`
- layouts/scenarios: `120`
- anchors per layout: `4`
- carrier frequencies: `0.915, 1.8, 2.4, 4.5, and 5.2 GHz`
- transmit powers: `-4, 0, 4, and 8 dBm`
- sparse ratios: `1%, 3%, 5%, 10%, and 20%`
- sparse sampling modes: random, clustered, and corridor/path-based

The full default simulation therefore produces:

```text
120 layouts x 4 anchors x 5 frequencies x 4 powers = 9600 dense radio-map samples
```

For each dense sample, sparse measurement variants are stored for the configured
sparse ratios and sampling modes.

## How to Run

From MATLAB, run:

```matlab
run("matlab/generate_ble_radio_map_dataset.m")
```

By default, outputs are written relative to the repository root:

```text
data/sim_ble_radio_maps/
results/figures/sim_preview/
```

The generated `data/sim_ble_radio_maps/` folder contains:

- `sample_XXXX.mat` files
- `metadata.csv`
- `README.txt`

Each `sample_XXXX.mat` file contains:

```text
cfg
runCfg
scenario
anchor
radio
sparse
features
```

The `features.common` tensor contains:

1. wall/obstacle mask
2. transmitter heatmap
3. distance-to-transmitter prior
4. free-space path-loss prior
5. accumulated wall-loss prior
6. LOS/NLOS prior
7. normalized carrier-frequency channel
8. normalized transmit-power channel

Each `features.byRatio(k).input` then appends:

9. normalized sparse RSSI map
10. sparse sampling mask

The dense target RSSI map is stored as:

```text
features.targetRssi
```

## Optional Output Root

To generate the dataset outside the repository folder, set:

```matlab
setenv("RSSI_PROJECT_ROOT", "/path/to/output/root")
run("matlab/generate_ble_radio_map_dataset.m")
```

The script will then write outputs under:

```text
/path/to/output/root/data/sim_ble_radio_maps/
/path/to/output/root/results/figures/sim_preview/
```

## Data Availability Notes

This repository provides the simulation data-generation code. The full generated
`.mat` dataset is not committed to this repository because it can be regenerated
from the MATLAB script and may be large for normal GitHub storage.

The real BLE measurements used in the paper were collected and processed by the
authors and are not provided here as a public reference dataset. The CampusRSSI
dataset used for dense measured validation is a public dataset and should be
obtained from its original source and cited according to the manuscript.
