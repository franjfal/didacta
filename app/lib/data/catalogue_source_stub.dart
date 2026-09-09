/// A file-backed catalogue, on a platform that has no files.
library;

import 'catalogue_source.dart';

CatalogueSource? fileSource(String directory) => null;
