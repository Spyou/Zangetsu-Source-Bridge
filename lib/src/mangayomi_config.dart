import 'package:d4rt/d4rt.dart';

import 'models.dart';

Map<String, dynamic> preferenceMap(Object? value) {
  if (value is BridgedInstance) value = value.nativeObject;
  if (value is Map) {
    final result = Map<String, dynamic>.from(value);
    for (final kind in [
      'listPreference',
      'multiSelectListPreference',
      'editTextPreference',
      'switchPreferenceCompat',
      'checkBoxPreference',
    ]) {
      if (result[kind] is Map) {
        final inner = Map<String, dynamic>.from(result[kind]);
        return {
          'key': result['key'],
          'type': switch (kind) {
            'listPreference' => 'list',
            'multiSelectListPreference' => 'multi',
            'editTextPreference' => 'text',
            'switchPreferenceCompat' => 'switch',
            _ => 'checkbox',
          },
          ...inner,
          if (kind == 'listPreference' && inner['entryValues'] is List)
            'value': (inner['entryValues'] as List).elementAtOrNull(
              inner['valueIndex'] is int ? inner['valueIndex'] as int : 0,
            ),
          if (kind == 'multiSelectListPreference')
            'value': inner['values'] ?? const [],
        };
      }
    }
    return result;
  }
  if (value is ListPreference) {
    return {
      'key': value.key,
      'type': 'list',
      'title': value.title,
      'summary': value.summary,
      'valueIndex': value.valueIndex,
      'entries': value.entries,
      'entryValues': value.entryValues,
      'value': value.entryValues?.elementAtOrNull(value.valueIndex ?? 0),
    };
  }
  if (value is MultiSelectListPreference) {
    return {
      'key': value.key,
      'type': 'multi',
      'title': value.title,
      'summary': value.summary,
      'entries': value.entries,
      'entryValues': value.entryValues,
      'value': value.values ?? const [],
    };
  }
  if (value is EditTextPreference) {
    return {
      'key': value.key,
      'type': 'text',
      'title': value.title,
      'summary': value.summary,
      'value': value.value,
    };
  }
  if (value is SwitchPreferenceCompat) {
    return {
      'key': value.key,
      'type': 'switch',
      'title': value.title,
      'summary': value.summary,
      'value': value.value,
    };
  }
  if (value is CheckBoxPreference) {
    return {
      'key': value.key,
      'type': 'checkbox',
      'title': value.title,
      'summary': value.summary,
      'value': value.value,
    };
  }
  throw FormatException('Unsupported source preference: ${value.runtimeType}');
}

Map<String, dynamic> filterMap(Object? value) {
  if (value is BridgedInstance) value = value.nativeObject;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is SelectFilter) {
    return {
      'type_name': 'SelectFilter',
      'type': value.type,
      'name': value.name,
      'state': value.state,
      'values': value.values.map(filterMap).toList(),
    };
  }
  if (value is SelectFilterOption) {
    return {
      'type_name': 'SelectOption',
      'name': value.name,
      'value': value.value,
    };
  }
  if (value is TextFilter) {
    return {
      'type_name': 'TextFilter',
      'type': value.type,
      'name': value.name,
      'state': value.state,
    };
  }
  if (value is CheckBoxFilter) {
    return {
      'type_name': 'CheckBoxFilter',
      'type': value.type,
      'name': value.name,
      'value': value.value,
      'state': value.state,
    };
  }
  if (value is TriStateFilter) {
    return {
      'type_name': 'TriStateFilter',
      'type': value.type,
      'name': value.name,
      'value': value.value,
      'state': value.state,
    };
  }
  if (value is GroupFilter) {
    return {
      'type_name': 'GroupFilter',
      'type': value.type,
      'name': value.name,
      'state': value.state.map(filterMap).toList(),
    };
  }
  if (value is SortFilter) {
    return {
      'type_name': 'SortFilter',
      'type': value.type,
      'name': value.name,
      'state': {'index': value.state.index, 'ascending': value.state.ascending},
      'values': value.values.map(filterMap).toList(),
    };
  }
  if (value is HeaderFilter) {
    return {
      'type_name': 'HeaderFilter',
      'type': value.type,
      'name': value.name,
    };
  }
  if (value is SeparatorFilter) {
    return {'type_name': 'SeparatorFilter', 'type': value.type};
  }
  throw FormatException('Unsupported source filter: ${value.runtimeType}');
}

dynamic dartFilter(Map<String, dynamic> value) {
  final type = value['type'] as String?;
  final name = value['name']?.toString() ?? '';
  switch (value['type_name']) {
    case 'SelectFilter':
      return SelectFilter(
        type,
        name,
        value['state'] as int? ?? 0,
        (value['values'] as List)
            .map((e) => dartFilter(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    case 'SelectOption':
      return SelectFilterOption(name, value['value']?.toString() ?? '');
    case 'TextFilter':
      return TextFilter(type, name, null, value['state']?.toString() ?? '');
    case 'CheckBoxFilter':
      return CheckBoxFilter(
        name,
        value['value']?.toString() ?? '',
        type,
        value['state'] == true,
      );
    case 'TriStateFilter':
      return TriStateFilter(
        name,
        value['value']?.toString() ?? '',
        type,
        null,
        value['state'] as int? ?? 0,
      );
    case 'GroupFilter':
      return GroupFilter(
        type,
        name,
        (value['state'] as List)
            .map((e) => dartFilter(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    case 'SortFilter':
      final state = Map<String, dynamic>.from(value['state'] as Map);
      return SortFilter(
        type,
        name,
        SortState(state['index'] as int? ?? 0, state['ascending'] == true),
        (value['values'] as List)
            .map((e) => dartFilter(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    case 'HeaderFilter':
      return HeaderFilter(name);
    case 'SeparatorFilter':
      return SeparatorFilter();
    default:
      throw FormatException('Unsupported source filter ${value['type_name']}');
  }
}
