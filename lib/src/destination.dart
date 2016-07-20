library linkcheck.destination;

import 'dart:io' show ContentType, HttpClientResponse, RedirectInfo;

class BasicRedirectInfo {
  String url;
  int statusCode;

  BasicRedirectInfo.from(RedirectInfo info) {
    url = info.location.toString();
    statusCode = info.statusCode;
  }

  BasicRedirectInfo.fromMap(Map<String, Object> map)
      : url = map["url"],
        statusCode = map["statusCode"];

  Map<String, Object> toMap() => {"url": url, "statusCode": statusCode};
}

class Destination {
  static const List<String> supportedSchemes = const ["http", "https", "file"];

  final String url;

  /// The uri as specified by source file, without the fragment.
  Uri _uri;

  /// The fragments referenced by origins.
  final Set<String> fragments = new Set<String>();

  /// The HTTP status code returned.
  int statusCode;

  /// MimeType of the response.
  ContentType contentType;

  List<BasicRedirectInfo> redirects;

  /// Url after all redirects.
  String finalUrl;

  bool isExternal;

  /// True if this [Destination] is parseable and could contain links to
  /// other destinations. For example, HTML and CSS files are sources. JPEGs
  /// and
  bool isSource = false;

  /// Set of anchors on the page.
  ///
  /// Only for [isSource] == `true`.
  List<String> anchors;

  bool isInvalid = false;

  bool didNotConnect = false;

  int _hashCode;

  Uri _finalUri;

  Destination(Uri uri)
      : url = uri.removeFragment().toString(),
        _uri = uri.removeFragment() {
    _hashCode = url.hashCode;
    if (uri.fragment.isNotEmpty) fragments.add(uri.fragment);
  }

  factory Destination.fromMap(Map<String, Object> map) {
    var destination = new Destination.fromString(map["url"]);
    var contentType = map["primaryType"] == null
        ? null
        : new ContentType(map["primaryType"], map["subType"]);
    destination
      ..statusCode = map["statusCode"]
      ..contentType = contentType
      ..redirects = (map["redirects"] as List<Map<String, Object>>)
          ?.map((obj) => new BasicRedirectInfo.fromMap(obj))
          ?.toList()
      ..finalUrl = map["finalUrl"]
      ..isExternal = map["isExternal"]
      ..isSource = map["isSource"]
      ..anchors = map["anchors"] as List<String>
      ..isInvalid = map["isInvalid"]
      ..didNotConnect = map["didNotConnect"];
    return destination;
  }

  Destination.fromString(String url)
      : url = url.contains("#") ? url.split("#").first : url {
    _hashCode = this.url.hashCode;
    if (url.contains("#")) {
      // Take everything after the first #
      String fragment = url.split("#").skip(1).join("#");
      fragments.add(fragment);
    }
  }

  /// Parsed [finalUrl].
  Uri get finalUri => _finalUri ??= Uri.parse(finalUrl ?? url);

  int get hashCode => _hashCode;

  /// Link that wasn't valid, didn't connect, or the [statusCode] was not
  /// HTTP 200 OK.
  ///
  /// Ignores URIs with unsupported scheme (like `mailto:`).
  bool get isBroken => statusCode != 200;

  bool get isCssMimeType =>
      contentType.primaryType == "text" && contentType.subType == "css";

  bool get isHtmlMimeType => contentType.mimeType == ContentType.HTML.mimeType;

  bool get isParseableMimeType => isHtmlMimeType || isCssMimeType;

  bool get isPermanentlyRedirected =>
      redirects != null &&
      redirects.isNotEmpty &&
      redirects.first.statusCode == 301;

  bool get isRedirected => redirects != null && redirects.isNotEmpty;

  /// True if the destination URI isn't one of the [supportedSchemes].
  bool get isUnsupportedScheme => !supportedSchemes.contains(finalUri.scheme);
  String get statusDescription {
    if (isInvalid) return "invalid URL";
    if (didNotConnect) return "connection failed";
    if (isUnsupportedScheme) return "scheme unsupported";
    if (!wasTried) return "wasn't tried";
    if (statusCode == 200) return "HTTP 200";
    if (isRedirected) {
      var path = redirects.map((redirect) => redirect.statusCode).join(" -> ");
      return "HTTP $path => $statusCode";
    }
    return "HTTP $statusCode";
  }

  Uri get uri => _uri ??= Uri.parse(url);

  bool get wasTried => didNotConnect || statusCode != null;

  bool operator ==(other) => other is Destination && other.hashCode == hashCode;

  Map<String, Object> toMap() => {
        "url": url,
        "statusCode": statusCode,
        "primaryType": contentType?.primaryType,
        "subType": contentType?.subType,
        "redirects": redirects?.map((info) => info.toMap())?.toList(),
        "finalUrl": finalUrl,
        "isExternal": isExternal,
        "isSource": isSource,
        "anchors": anchors,
        "isInvalid": isInvalid,
        "didNotConnect": didNotConnect
      };

  String toString() => "$url${fragments.isEmpty
      ? ''
      : '#(' + fragments.join('|') + ')'}";

  void updateFragmentsFrom(Destination other) {
    if (other.fragments.isEmpty) return;
    fragments.addAll(other.fragments);
  }

  void updateFromResult(DestinationResult result) {
    assert(url == result.url);
    finalUrl = result.finalUrl;
    statusCode = result.statusCode;
    contentType = result.primaryType == null
        ? null
        : new ContentType(result.primaryType, result.subType);
    redirects = result.redirects;
    isSource = result.isSource;
    anchors = result.anchors;
    didNotConnect = result.didNotConnect;
  }
}

/// Data about destination coming from a fetch.
class DestinationResult {
  String url;
  String finalUrl;
  int statusCode;
  String primaryType;
  String subType;
  List<BasicRedirectInfo> redirects;
  bool isSource = false;
  List<String> anchors;
  bool didNotConnect = false;

  DestinationResult.fromDestination(Destination destination)
      : url = destination.url,
        isSource = destination.isSource;

  DestinationResult.fromMap(Map<String, Object> map)
      : url = map["url"],
        finalUrl = map["finalUrl"],
        statusCode = map["statusCode"],
        primaryType = map["primaryType"],
        subType = map["subType"],
        redirects = (map["redirects"] as List<Map<String, Object>>)
            .map((obj) => new BasicRedirectInfo.fromMap(obj))
            .toList(),
        isSource = map["isSource"],
        anchors = map["anchors"] as List<String>,
        didNotConnect = map["didNotConnect"];

  Map<String, Object> toMap() => {
        "url": url,
        "finalUrl": finalUrl,
        "statusCode": statusCode,
        "primaryType": primaryType,
        "subType": subType,
        "redirects": redirects.map((info) => info.toMap()).toList(),
        "isSource": isSource,
        "anchors": anchors,
        "didNotConnect": didNotConnect
      };

  void updateFromResponse(HttpClientResponse response) {
    statusCode = response.statusCode;
    redirects = response.redirects
        .map((info) => new BasicRedirectInfo.from(info))
        .toList();
    if (redirects.isEmpty) {
      finalUrl = url;
    } else {
      finalUrl = redirects
          .fold(
              Uri.parse(url),
              (Uri current, BasicRedirectInfo redirect) =>
                  current.resolve(redirect.url))
          .toString();
    }
    primaryType = response.headers.contentType.primaryType;
    subType = response.headers.contentType.subType;
  }
}
