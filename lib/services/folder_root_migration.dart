/// The SAF document identity is independent of the tree used to grant access.
String? externalDocumentId(String uri, {bool tree = false}) {
  final parsed = Uri.tryParse(uri);
  if (parsed?.scheme != 'content' ||
      parsed?.authority != 'com.android.externalstorage.documents') {
    return null;
  }
  final segments = parsed!.pathSegments;
  final index = segments.lastIndexOf(tree ? 'tree' : 'document');
  return index >= 0 && index + 1 < segments.length ? segments[index + 1] : null;
}

/// Reuses the same physical file under a newly selected parent grant. When the
/// scanner can walk raw paths, use that exact key so rescanning retains song IDs.
String migrateFolderSongPath(String path, String parentUri, {String? rawRoot}) {
  final document = externalDocumentId(path);
  final root = externalDocumentId(parentUri, tree: true);
  if (document == null || root == null) return path;
  final prefix = root.endsWith(':') ? root : '$root/';
  if (!document.toLowerCase().startsWith(prefix.toLowerCase())) return path;
  if (rawRoot != null) {
    final relative = document.substring(prefix.length);
    return '${rawRoot.replaceFirst(RegExp(r'/+$'), '')}/$relative';
  }
  final parsed = Uri.parse(parentUri);
  return Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    pathSegments: ['tree', root, 'document', document],
  ).toString();
}

String? migratedRelativeFolder(
  String path,
  String parentUri, {
  String? rawRoot,
}) {
  final root = externalDocumentId(parentUri, tree: true);
  final document = externalDocumentId(path);
  String? relative;
  if (root != null && document != null) {
    final prefix = root.endsWith(':') ? root : '$root/';
    if (document.toLowerCase().startsWith(prefix.toLowerCase())) {
      relative = document.substring(prefix.length);
    }
  } else if (rawRoot != null && path.startsWith('$rawRoot/')) {
    relative = path.substring(rawRoot.length + 1);
  }
  if (relative == null) return null;
  final separator = relative.lastIndexOf('/');
  return separator < 0 ? '' : relative.substring(0, separator);
}
