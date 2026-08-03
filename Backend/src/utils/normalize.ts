export function normalizeString(s?: string): string {
  if (!s) return "";
  return s
    .trim()
    .toLowerCase()
    .replace(/[^\w\s-]/g, "")
    .replace(/\s+/g, " ");
}

export function normalizeArray(a?: string[]): string[] {
  return (a ?? []).map(normalizeString).filter(Boolean);
}

export function normalizeSortedArray(a?: string[]): string[] {
  return normalizeArray(a).sort();
}

export function makeNormKey(title?: string, album?: string, artists?: string[]): string {
  const normTitle = normalizeString(title);
  const normAlbum = normalizeString(album);
  const normArtists = normalizeSortedArray(artists);
  return `${normTitle}@@${normAlbum}@@${normArtists.join("|")}`;
}