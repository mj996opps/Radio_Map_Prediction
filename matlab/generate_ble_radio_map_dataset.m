function generate_ble_radio_map_dataset()
%GENERATE_BLE_RADIO_MAP_DATASET Generate multi-band IoT-style indoor RSSI radio maps.
%
% The simulator creates environment-aware radio-map samples for the IEEE
% Access RSSI project. It is intentionally lightweight and reproducible:
% floor plans, wall attenuation, anchor locations, dense RSSI maps, and
% sparse measurement masks are saved in a MATLAB-friendly format.

cfg = defaultConfig();
rng(cfg.randomSeed, 'twister');

projectRoot = getProjectRoot();
outputDir = fullfile(projectRoot, 'data', 'sim_ble_radio_maps');
figureDir = fullfile(projectRoot, 'results', 'figures', 'sim_preview');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

metadata = table();
sampleIndex = 0;

for scenarioIndex = 1:cfg.numScenarios
    scenario = generateScenario(cfg, scenarioIndex);

    for anchorIndex = 1:cfg.anchorsPerScenario
        anchor = chooseAnchorLocation(scenario, cfg);
        geometry = computeAnchorGeometry(scenario, anchor, cfg);

        for frequencyIndex = 1:numel(cfg.frequencyHzList)
            for powerIndex = 1:numel(cfg.txPowerDbmList)
                runCfg = cfg;
                runCfg.frequencyHz = cfg.frequencyHzList(frequencyIndex);
                runCfg.txPowerDbm = cfg.txPowerDbmList(powerIndex);

                sampleIndex = sampleIndex + 1;
                anchor.frequencyHz = runCfg.frequencyHz;
                anchor.txPowerDbm = runCfg.txPowerDbm;
                radio = computeRadioMap(scenario, anchor, runCfg, geometry);
                sparse = createSparseMeasurements(radio.rssiMap, scenario, runCfg);
                features = buildFeatureTensor(scenario, anchor, radio, sparse, runCfg);

                sampleId = sprintf('sample_%04d', sampleIndex);
                sampleFile = fullfile(outputDir, [sampleId '.mat']);
                save(sampleFile, 'cfg', 'runCfg', 'scenario', 'anchor', 'radio', 'sparse', 'features', '-v7');

                validRssi = radio.rssiMap(~isnan(radio.rssiMap));
                row = table( ...
                    {char(sampleId)}, scenarioIndex, anchorIndex, frequencyIndex, powerIndex, ...
                    anchor.xMeters, anchor.yMeters, runCfg.frequencyHz/1e9, runCfg.txPowerDbm, ...
                    radio.pathLossExponent, radio.shadowSigmaDb, ...
                    mean(validRssi), min(validRssi), max(validRssi), ...
                    'VariableNames', {'sample_id', 'scenario_id', 'anchor_id', ...
                    'frequency_id', 'power_id', 'tx_x_m', 'tx_y_m', 'frequency_ghz', ...
                    'tx_power_dbm', 'path_loss_exponent', 'shadow_sigma_db', ...
                    'mean_rssi_dbm', 'min_rssi_dbm', 'max_rssi_dbm'});
                metadata = [metadata; row]; %#ok<AGROW>

                if sampleIndex <= cfg.numPreviewFigures
                    plotPreview(scenario, anchor, radio, sparse, runCfg, ...
                        fullfile(figureDir, [sampleId '.png']));
                end
            end
        end
    end
end

writetable(metadata, fullfile(outputDir, 'metadata.csv'));
writeDatasetReadme(outputDir, cfg);

fprintf('Generated %d samples in %s\n', sampleIndex, outputDir);
fprintf('Preview figures written to %s\n', figureDir);
end

function projectRoot = getProjectRoot()
projectRoot = getenv('RSSI_PROJECT_ROOT');
if isempty(projectRoot)
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(thisFile));
end
end

function cfg = defaultConfig()
cfg.randomSeed = 42;
cfg.numScenarios = 120;
cfg.anchorsPerScenario = 4;
cfg.numPreviewFigures = 12;

cfg.gridSize = [96, 96];
cfg.cellSizeMeters = 0.25;
cfg.frequencyHzList = [0.915e9, 1.8e9, 2.4e9, 4.5e9, 5.2e9];
cfg.txPowerDbmList = [-4, 0, 4, 8];
cfg.frequencyHz = cfg.frequencyHzList(1);
cfg.txPowerDbm = cfg.txPowerDbmList(1);
cfg.referenceDistanceMeters = 1;
cfg.receiverHeightMeters = 1.2;
cfg.transmitterHeightMeters = 1.5;

cfg.pathLossExponentRange = [1.6, 2.4];
cfg.shadowSigmaRangeDb = [1.5, 4.0];
cfg.wallLossRangeDb = [3.0, 8.0];
cfg.doorWidthCells = 5;
cfg.minAnchorWallDistanceCells = 4;
cfg.rssiFloorDbm = -115;
cfg.rssiCeilingDbm = -25;

cfg.sparseRatios = [0.01, 0.03, 0.05, 0.10, 0.20];
cfg.sparseSamplingModes = {'random', 'clustered', 'corridor'};
cfg.clusterCountRange = [3, 6];
cfg.clusterRadiusCells = [4, 9];
cfg.corridorHalfWidthCells = 2;
cfg.corridorNumPathsRange = [2, 4];
cfg.corridorMinFreeFraction = 0.55;
cfg.noiseSigmaDb = 1.5;
cfg.coverageThresholdDbm = -80;

if strcmp(getenv('RSSI_SIM_SMOKE'), '1')
    cfg.numScenarios = 1;
    cfg.anchorsPerScenario = 1;
    cfg.numPreviewFigures = 1;
    cfg.frequencyHzList = 2.4e9;
    cfg.txPowerDbmList = 0;
end
end

function scenario = generateScenario(cfg, scenarioIndex)
height = cfg.gridSize(1);
width = cfg.gridSize(2);

wallMask = false(height, width);
wallLossMap = zeros(height, width);

wallMask(1, :) = true;
wallMask(end, :) = true;
wallMask(:, 1) = true;
wallMask(:, end) = true;

numVertical = randi([2, 4]);
numHorizontal = randi([2, 4]);

for k = 1:numVertical
    col = randi([round(width*0.18), round(width*0.82)]);
    wallMask(:, col) = true;
    doorCenter = randi([10, height-10]);
    doorRange = max(2, doorCenter - cfg.doorWidthCells):min(height-1, doorCenter + cfg.doorWidthCells);
    wallMask(doorRange, col) = false;
end

for k = 1:numHorizontal
    row = randi([round(height*0.18), round(height*0.82)]);
    wallMask(row, :) = true;
    doorCenter = randi([10, width-10]);
    doorRange = max(2, doorCenter - cfg.doorWidthCells):min(width-1, doorCenter + cfg.doorWidthCells);
    wallMask(row, doorRange) = false;
end

numBlocks = randi([2, 5]);
for k = 1:numBlocks
    blockHeight = randi([4, 10]);
    blockWidth = randi([4, 14]);
    row = randi([8, height-blockHeight-8]);
    col = randi([8, width-blockWidth-8]);
    wallMask(row:row+blockHeight, col:col+blockWidth) = true;
end

wallLossMap(wallMask) = cfg.wallLossRangeDb(1) + ...
    diff(cfg.wallLossRangeDb) .* rand(nnz(wallMask), 1);

scenario.id = scenarioIndex;
scenario.wallMask = wallMask;
scenario.wallLossMap = wallLossMap;
scenario.cellSizeMeters = cfg.cellSizeMeters;
scenario.widthMeters = width * cfg.cellSizeMeters;
scenario.heightMeters = height * cfg.cellSizeMeters;
end

function anchor = chooseAnchorLocation(scenario, cfg)
freeMask = ~scenario.wallMask;
wallNeighborhood = conv2(double(scenario.wallMask), ...
    ones(2*cfg.minAnchorWallDistanceCells + 1), 'same');
candidateMask = freeMask & wallNeighborhood == 0;
[rows, cols] = find(candidateMask);
if isempty(rows)
    [rows, cols] = find(freeMask);
end
selected = randi(numel(rows));
row = rows(selected);
col = cols(selected);

anchor.row = row;
anchor.col = col;
anchor.xMeters = (col - 0.5) * cfg.cellSizeMeters;
anchor.yMeters = (row - 0.5) * cfg.cellSizeMeters;
anchor.frequencyHz = cfg.frequencyHz;
anchor.txPowerDbm = cfg.txPowerDbm;
end

function geometry = computeAnchorGeometry(scenario, anchor, cfg)
[height, width] = size(scenario.wallMask);
[colGrid, rowGrid] = meshgrid(1:width, 1:height);

xMeters = (colGrid - 0.5) * cfg.cellSizeMeters;
yMeters = (rowGrid - 0.5) * cfg.cellSizeMeters;
distanceMeters = hypot(xMeters - anchor.xMeters, yMeters - anchor.yMeters);
distanceMeters = max(distanceMeters, cfg.referenceDistanceMeters);
wallAccumulationDb = computeWallAccumulation(scenario.wallLossMap, anchor.row, anchor.col);

geometry.distanceMeters = distanceMeters;
geometry.wallAccumulationDb = wallAccumulationDb;
geometry.losMap = wallAccumulationDb < 0.5;
end

function radio = computeRadioMap(scenario, ~, cfg, geometry)
[height, width] = size(scenario.wallMask);
distanceMeters = geometry.distanceMeters;
pathLossExponent = cfg.pathLossExponentRange(1) + diff(cfg.pathLossExponentRange) * rand();
shadowSigmaDb = cfg.shadowSigmaRangeDb(1) + diff(cfg.shadowSigmaRangeDb) * rand();
wallAccumulationDb = geometry.wallAccumulationDb;
losMap = geometry.losMap;

c = 299792458;
fsplDb = 20*log10(4*pi*distanceMeters*cfg.frequencyHz/c);
largeScaleLossDb = fsplDb + 10*(pathLossExponent - 2).*log10(distanceMeters) + wallAccumulationDb;

shadowingDb = gaussianSmooth2d(randn(height, width) * shadowSigmaDb, 1.5);

reflectionResidualDb = 2.0 * exp(-wallAccumulationDb/12) .* sin(0.55*distanceMeters + 0.7*rand());
noiseDb = cfg.noiseSigmaDb * randn(height, width);

rssiMap = cfg.txPowerDbm - largeScaleLossDb + shadowingDb + reflectionResidualDb + noiseDb;
rssiMap = min(max(rssiMap, cfg.rssiFloorDbm), cfg.rssiCeilingDbm);
rssiMap(scenario.wallMask) = NaN;

radio.distanceMeters = distanceMeters;
radio.fsplDb = fsplDb;
radio.wallAccumulationDb = wallAccumulationDb;
radio.losMap = losMap;
radio.rssiMap = rssiMap;
radio.coverageMap = rssiMap >= cfg.coverageThresholdDbm;
radio.pathLossExponent = pathLossExponent;
radio.shadowSigmaDb = shadowSigmaDb;
radio.frequencyHz = cfg.frequencyHz;
radio.txPowerDbm = cfg.txPowerDbm;
end

function wallAccumulationDb = computeWallAccumulation(wallLossMap, anchorRow, anchorCol)
[height, width] = size(wallLossMap);
wallAccumulationDb = zeros(height, width);

for row = 1:height
    for col = 1:width
        wallAccumulationDb(row, col) = sampleLineLoss(wallLossMap, anchorRow, anchorCol, row, col);
    end
end
end

function lossDb = sampleLineLoss(wallLossMap, row0, col0, row1, col1)
numSteps = max(abs(row1 - row0), abs(col1 - col0)) + 1;
rows = round(linspace(row0, row1, numSteps));
cols = round(linspace(col0, col1, numSteps));
rows = min(max(rows, 1), size(wallLossMap, 1));
cols = min(max(cols, 1), size(wallLossMap, 2));
indices = sub2ind(size(wallLossMap), rows, cols);
lossSamples = wallLossMap(indices);
wallSequence = lossSamples > 0;

if ~any(wallSequence)
    lossDb = 0;
else
    segmentStarts = wallSequence & [true, ~wallSequence(1:end-1)];
    lossDb = sum(lossSamples(segmentStarts));
end
end

function sparse = createSparseMeasurements(rssiMap, scenario, cfg)
validMask = ~isnan(rssiMap);
sparse = struct();
itemIndex = 0;

for k = 1:numel(cfg.sparseRatios)
    ratio = cfg.sparseRatios(k);
    for m = 1:numel(cfg.sparseSamplingModes)
        samplingMode = cfg.sparseSamplingModes{m};
        observedMask = createSparseMask(validMask, scenario, ratio, samplingMode, cfg);

        sparseMap = zeros(size(rssiMap));
        sparseMap(observedMask) = rssiMap(observedMask);

        itemIndex = itemIndex + 1;
        sparse(itemIndex).ratio = ratio; %#ok<AGROW>
        sparse(itemIndex).samplingMode = samplingMode; %#ok<AGROW>
        sparse(itemIndex).mask = observedMask; %#ok<AGROW>
        sparse(itemIndex).map = sparseMap; %#ok<AGROW>
    end
end
end

function observedMask = createSparseMask(validMask, scenario, ratio, samplingMode, cfg)
validIndices = find(validMask);
numObserved = max(1, round(ratio * numel(validIndices)));

switch samplingMode
    case 'random'
        candidateMask = validMask;
        selected = sampleFromCandidates(candidateMask, validMask, numObserved);
    case 'clustered'
        selected = sampleClustered(validMask, numObserved, cfg);
    case 'corridor'
        candidateMask = createCorridorCandidateMask(validMask, scenario, cfg);
        selected = sampleFromCandidates(candidateMask, validMask, numObserved);
    otherwise
        error('Unknown sparse sampling mode: %s', samplingMode);
end

observedMask = false(size(validMask));
observedMask(selected) = true;
end

function selected = sampleFromCandidates(candidateMask, validMask, numObserved)
candidateIndices = find(candidateMask & validMask);
if numel(candidateIndices) < numObserved
    fallbackIndices = find(validMask);
    candidateIndices = unique([candidateIndices; fallbackIndices]);
end
order = randperm(numel(candidateIndices), min(numObserved, numel(candidateIndices)));
selected = candidateIndices(order);
end

function selected = sampleClustered(validMask, numObserved, cfg)
[rows, cols] = find(validMask);
numClusters = randi(cfg.clusterCountRange);
centerOrder = randperm(numel(rows), min(numClusters, numel(rows)));
candidateMask = false(size(validMask));

for k = 1:numel(centerOrder)
    centerRow = rows(centerOrder(k));
    centerCol = cols(centerOrder(k));
    radius = randi(cfg.clusterRadiusCells);
    rowMin = max(1, centerRow - radius);
    rowMax = min(size(validMask, 1), centerRow + radius);
    colMin = max(1, centerCol - radius);
    colMax = min(size(validMask, 2), centerCol + radius);
    [cc, rr] = meshgrid(colMin:colMax, rowMin:rowMax);
    localMask = (rr - centerRow).^2 + (cc - centerCol).^2 <= radius^2;
    candidateMask(rowMin:rowMax, colMin:colMax) = ...
        candidateMask(rowMin:rowMax, colMin:colMax) | localMask;
end

selected = sampleFromCandidates(candidateMask, validMask, numObserved);
end

function candidateMask = createCorridorCandidateMask(validMask, scenario, cfg)
[height, width] = size(validMask);
freeMask = validMask & ~scenario.wallMask;
candidateMask = false(height, width);
numPaths = randi(cfg.corridorNumPathsRange);

for k = 1:numPaths
    if rand() < 0.5
        rowScores = sum(freeMask, 2) ./ width;
        candidateRows = find(rowScores >= cfg.corridorMinFreeFraction);
        candidateRows = candidateRows(candidateRows > 2 & candidateRows < height-1);
        if isempty(candidateRows)
            candidateRows = find(any(freeMask, 2));
        end
        centerRow = candidateRows(randi(numel(candidateRows)));
        rowRange = max(1, centerRow - cfg.corridorHalfWidthCells): ...
            min(height, centerRow + cfg.corridorHalfWidthCells);
        candidateMask(rowRange, :) = true;
    else
        colScores = sum(freeMask, 1) ./ height;
        candidateCols = find(colScores >= cfg.corridorMinFreeFraction);
        candidateCols = candidateCols(candidateCols > 2 & candidateCols < width-1);
        if isempty(candidateCols)
            candidateCols = find(any(freeMask, 1));
        end
        centerCol = candidateCols(randi(numel(candidateCols)));
        colRange = max(1, centerCol - cfg.corridorHalfWidthCells): ...
            min(width, centerCol + cfg.corridorHalfWidthCells);
        candidateMask(:, colRange) = true;
    end
end

candidateMask = candidateMask & freeMask;
if nnz(candidateMask) < 1
    candidateMask = freeMask;
end
end

function features = buildFeatureTensor(scenario, anchor, radio, sparse, cfg)
[height, width] = size(scenario.wallMask);
txMap = zeros(height, width);
txMap(anchor.row, anchor.col) = 1;
txMap = gaussianSmooth2d(txMap, 1.25);

environmentMap = double(scenario.wallMask);
distanceNorm = normalizeMap(radio.distanceMeters);
fsplNorm = normalizeMap(radio.fsplDb);
wallLossNorm = normalizeMap(radio.wallAccumulationDb);
losMap = double(radio.losMap);
frequencyNorm = ones(height, width) .* normalizeScalar(cfg.frequencyHz, 0.8e9, 6.0e9);
txPowerNorm = ones(height, width) .* normalizeScalar(cfg.txPowerDbm, -10, 20);

features.common = cat(3, environmentMap, txMap, distanceNorm, fsplNorm, ...
    wallLossNorm, losMap, frequencyNorm, txPowerNorm);

for k = 1:numel(sparse)
    sparseMap = sparse(k).map;
    sparseNorm = sparseMap;
    observedValues = sparseMap(sparse(k).mask);
    if ~isempty(observedValues)
        sparseNorm(sparse(k).mask) = (observedValues - mean(observedValues)) ./ max(std(observedValues), eps);
    end
    features.byRatio(k).ratio = sparse(k).ratio; %#ok<AGROW>
    features.byRatio(k).input = cat(3, features.common, sparseNorm, double(sparse(k).mask)); %#ok<AGROW>
end

features.targetRssi = radio.rssiMap;
features.targetCoverage = radio.coverageMap;
features.channelNames = {'wall_mask', 'tx_heatmap', 'distance_norm', 'fspl_norm', ...
    'wall_loss_norm', 'los_map', 'frequency_norm', 'tx_power_norm', ...
    'sparse_rssi_norm', 'sparse_mask'};
end

function mapOut = normalizeMap(mapIn)
valid = ~isnan(mapIn);
mapOut = zeros(size(mapIn));
values = mapIn(valid);
mapOut(valid) = (values - min(values)) ./ max(max(values) - min(values), eps);
end

function valueOut = normalizeScalar(valueIn, minValue, maxValue)
valueOut = (valueIn - minValue) ./ max(maxValue - minValue, eps);
valueOut = min(max(valueOut, 0), 1);
end

function plotPreview(scenario, anchor, radio, sparse, ~, outputFile)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1200 700]);

subplot(2, 3, 1);
imagesc(scenario.wallMask);
axis image off;
colormap(gca, gray);
title('Environment');
hold on;
plot(anchor.col, anchor.row, 'rp', 'MarkerSize', 12, 'MarkerFaceColor', 'r');

subplot(2, 3, 2);
imagesc(radio.fsplDb);
axis image off;
colorbar;
title('FSPL prior (dB)');

subplot(2, 3, 3);
imagesc(radio.wallAccumulationDb);
axis image off;
colorbar;
title('Accumulated wall loss (dB)');

subplot(2, 3, 4);
imagesc(radio.rssiMap);
axis image off;
colorbar;
title('Dense RSSI map (dBm)');

subplot(2, 3, 5);
randomIndex = findSparseIndex(sparse, 0.05, 'random');
imagesc(sparse(randomIndex).map, 'AlphaData', sparse(randomIndex).mask | scenario.wallMask);
axis image off;
colorbar;
title(sprintf('Random sparse %.0f%%', 100*sparse(randomIndex).ratio));

subplot(2, 3, 6);
corridorIndex = findSparseIndex(sparse, 0.05, 'corridor');
imagesc(sparse(corridorIndex).map, 'AlphaData', sparse(corridorIndex).mask | scenario.wallMask);
axis image off;
colorbar;
title(sprintf('Corridor sparse %.0f%%', 100*sparse(corridorIndex).ratio));

try
    exportgraphics(fig, outputFile, 'Resolution', 180);
catch
    print(fig, outputFile, '-dpng', '-r180');
end
close(fig);
end

function index = findSparseIndex(sparse, ratio, samplingMode)
ratios = [sparse.ratio];
modeMatches = false(size(ratios));
for k = 1:numel(sparse)
    modeMatches(k) = isfield(sparse(k), 'samplingMode') && strcmp(sparse(k).samplingMode, samplingMode);
end
matches = find(abs(ratios - ratio) < 1e-9 & modeMatches, 1);
if isempty(matches)
    matches = find(abs(ratios - ratio) < 1e-9, 1);
end
if isempty(matches)
    matches = 1;
end
index = matches;
end

function smoothed = gaussianSmooth2d(mapIn, sigma)
radius = max(1, ceil(3*sigma));
x = -radius:radius;
kernel = exp(-(x.^2) ./ (2*sigma^2));
kernel = kernel ./ sum(kernel);
smoothed = conv2(conv2(mapIn, kernel, 'same'), kernel', 'same');
end

function writeDatasetReadme(outputDir, cfg)
readmeFile = fullfile(outputDir, 'README.txt');
fid = fopen(readmeFile, 'w');
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Multi-band IoT-style indoor RSSI radio map simulation dataset\n');
fprintf(fid, 'Generated by matlab/generate_ble_radio_map_dataset.m\n\n');
fprintf(fid, 'Grid: %d x %d cells, %.2f m per cell\n', cfg.gridSize(1), cfg.gridSize(2), cfg.cellSizeMeters);
fprintf(fid, 'Frequencies: %s GHz\n', mat2str(cfg.frequencyHzList/1e9));
fprintf(fid, 'Tx powers: %s dBm\n', mat2str(cfg.txPowerDbmList));
fprintf(fid, 'Scenarios: %d\n', cfg.numScenarios);
fprintf(fid, 'Anchors per scenario: %d\n', cfg.anchorsPerScenario);
fprintf(fid, 'Sparse ratios: %s\n', mat2str(cfg.sparseRatios));
fprintf(fid, 'Sparse sampling modes: %s\n', strjoin(cfg.sparseSamplingModes, ', '));
fprintf(fid, 'Coverage threshold: %.1f dBm\n\n', cfg.coverageThresholdDbm);
fprintf(fid, 'Each sample MAT file contains cfg, scenario, anchor, radio, sparse, and features.\n');
fprintf(fid, 'features.common contains wall mask, Tx heatmap, distance, FSPL, wall loss, LOS, frequency, and Tx power maps.\n');
fprintf(fid, 'features.byRatio(k).input adds sparse RSSI and sparse mask channels.\n');
fprintf(fid, 'features.targetRssi is the dense RSSI map in dBm.\n');
end
