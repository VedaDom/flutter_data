import 'package:flutter_data/flutter_data.dart';
import 'package:json_api/document.dart';

mixin JSONAPIAdapter<T extends DataSupportMixin<T>> on Repository<T> {
  @override
  get headers => super.headers
    ..addAll({
      'Content-Type': 'application/vnd.api+json',
      'Accept': 'application/vnd.api+json',
    });

  // Transforms native format into JSON:API
  @override
  Map<String, dynamic> serialize(model) {
    final map = super.serialize(model);

    final relationships = {};

    for (var relEntry in relationshipMetadata['HasMany'].entries) {
      final name = relEntry.key.toString();
      if (map[name] != null) {
        final keys = List<String>.from(map[name] as Iterable);
        final type = relEntry.value;
        final identifiers =
            DataId.byKeys(keys, manager, type: type.toString()).map((dataId) {
          return IdentifierObject(dataId.type, dataId.id);
        });
        relationships[name] = ToMany(identifiers);
        map.remove(name);
      }
    }

    for (var relEntry in relationshipMetadata['BelongsTo'].entries) {
      final name = relEntry.key.toString();
      if (map[name] != null) {
        final key = map[name].toString();
        final type = relEntry.value;
        final dataId = DataId.byKey(key, manager, type: type.toString());
        relationships[name] = ToOne(IdentifierObject(dataId.type, dataId.id));
        map.remove(name);
      }
    }

    final resource =
        ResourceObject(DataId.getType<T>(), map.id, attributes: map);
    map.remove('id');

    return Document(ResourceData(resource)).toJson();
  }

  @override
  deserializeCollection(object) {
    final doc = Document.fromJson(object, ResourceCollectionData.fromJson);
    final tuples = doc.data.collection.map((obj) => [obj, doc.data.included]);
    return super.deserializeCollection(tuples);
  }

  // Transforms JSON:API into native format
  @override
  T deserialize(object, {key}) {
    Map<String, dynamic> nativeMap = {};
    final includedDataIds = <DataId>[];
    final included = <ResourceObject>[];
    ResourceObject obj;

    if (object is Iterable) {
      obj = object.elementAt(0) as ResourceObject;
      if (object.elementAt(1) != null) {
        included.addAll(object.elementAt(1) as List<ResourceObject>);
      }
    } else if (object is ResourceObject) {
      obj = object;
    } else {
      final doc = Document.fromJson(object, ResourceData.fromJson);
      obj = doc.data.resourceObject;
      if (doc.data.included != null) {
        included.addAll(doc.data.included);
      }
    }

    nativeMap['id'] = obj.id;

    if (obj.relationships != null) {
      for (var relEntry in obj.relationships.entries) {
        final rel = relEntry.value;
        if (rel is ToOne && rel.linkage != null) {
          final type = DataId.getType(rel.linkage.type);
          final dataId = manager.dataId(rel.linkage.id, type: type);
          nativeMap[relEntry.key] = dataId.key;
          includedDataIds.add(dataId);
        } else if (rel is ToMany) {
          nativeMap[relEntry.key] = rel.linkage.map((i) {
            final type = DataId.getType(i.type);
            final dataId = manager.dataId(i.id, type: type);
            includedDataIds.add(dataId);
            return dataId.key;
          }).toList();
        }
      }
    }

    nativeMap.addAll(obj.attributes);

    // included
    for (var dataId in includedDataIds) {
      final obj = included.firstWhere(
          (r) => r.id == dataId.id && DataId.getType(r.type) == dataId.type,
          orElse: () => null);
      if (obj != null) {
        final type = DataId.getType(obj.type);
        final repo = relationshipMetadata['repository#$type'] as Repository;
        repo?.deserialize(obj);
      }
    }

    return super.deserialize(nativeMap, key: key);
  }
}
