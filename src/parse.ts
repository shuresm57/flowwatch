import { getFeatureNames } from "./model";

export function parseCSVRows(csv: string): number[][] {
  const lines = csv.trim().split("\n");
  if (lines.length === 0) return [];

  const featureNames = getFeatureNames();
  const firstLine = lines[0].split(",");

  // Check if first line is a header (non-numeric first value)
  const hasHeader = isNaN(Number(firstLine[0]));
  const dataLines = hasHeader ? lines.slice(1) : lines;

  if (hasHeader) {
    // Map columns by header name to expected feature order
    const headerMap = new Map(firstLine.map((h, i) => [h.trim(), i]));

    return dataLines.map((line) => {
      const values = line.split(",");
      return featureNames.map((name) => {
        const idx = headerMap.get(name);
        if (idx === undefined) return 0;
        return Number(values[idx]) || 0;
      });
    });
  }

  // No header — assume columns are in the correct order
  return dataLines.map((line) =>
    line
      .split(",")
      .slice(0, featureNames.length)
      .map((v) => Number(v) || 0)
  );
}
