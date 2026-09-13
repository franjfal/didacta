/// En web no hay disco que vigilar: el índice llega por HTTP.
library;

Stream<void> watchIndex(String directory) => const Stream.empty();

Stream<void> watchContent(String directory) => const Stream.empty();

Future<DateTime?> indexModified(String directory) async => null;
