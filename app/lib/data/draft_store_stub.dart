/// Sin disco: los borradores, en memoria.
library;

import 'draft_store.dart';

DraftStore diskDrafts() => MemoryDraftStore();
