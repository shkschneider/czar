#ifndef CZ_ARRAY_H
#define CZ_ARRAY_H

#define array_append(array, item) do { \
    if (array){ \
        __typeof__(array) _cza = array; \
        while (_cza->next != NULL) { \
            _cza = _cza->next; \
        } \
        _cza->next = item; \
    } else { \
        array = item; \
    } \
} while (0)

#define array_prepend(array, item) do { \
    if (array) { \
        item->next = array; \
    } \
    array = item; \
} while (0)

#define array_reverse(array) do { \
    __typeof__(array) _cza = array, _prev = NULL, _next; \
    while (_cza) { \
        _next = _cza->next; \
        _cza->next = _prev; \
        _prev = _cza; \
        _cza = _next; \
    } \
    array = _prev; \
} while (0)

#define array_last(array, item) do { \
    item = array; \
    while (item->next) { \
        item = item->next; \
    } \
} while (0)

#define array_concat(array1, array2) do { \
    if (array1) { \
        __typeof__(array1) _cza = array1; \
        while (_cza->next) { \
            _cza = _cza->next; \
        } \
        _cza->next = array2; \
    } else { \
        array1 = array2; \
    } \
} while (0)

#define array_length(array, length) do { \
    length = 0; \
    __typeof__(array) _cza = array; \
    while (_cza) { \
        length++; \
        _cza = _cza->next; \
    } \
} while (0)

#define array_foreach(array, item) \
    for (item = array; item; item = item->next)

#define array_delete(array, item) do { \
    __typeof__(array) _cza = array; \
    if (item == array) { \
        array = array->next; \
    } else { \
        while (_cza->next && _cza->next != item) { \
            _cza = _cza->next; \
        } \
        _cza->next = item->next; \
    } \
} while (0)

#endif
