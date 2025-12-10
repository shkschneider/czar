#ifndef CZ_LIST_H
#define CZ_LIST_H

#include <stdbool.h>

// https://github.com/nbulischeck/list.h

#define list_append(lst, node) do { \
    if (lst) { \
        __typeof__(lst) _czl = lst; \
        while (_czl->next != NULL) { \
            _czl = _czl->next; \
        } \
        node->prev = _czl; \
        _czl->next = node; \
    } else { \
        lst = node; \
    } \
} while (0)

#define list_prepend(lst, node) do \
    if (lst) { \
        node->next = list; \
        lst->prev = node; \
    } \
    lst = node; \
} while (0)

#define list_reverse(lst) do { \
    __typeof__(lst) _czl; \
    while (lst) { \
        _czl = lst->prev; \
        lst->prev = lst->next; \
        lst->next = _czl; \
        if (!lst->prev) { \
            break; \
        } \
        lst = lst->prev; \
    } \
} while (0)

#define list_last(lst, node) do { \
    node = lst; \
    while (node->next) { \
        node = node->next; \
    } \
} while (0)

#define list_concat(lst1, lst2) do { \
    if (lst1) { \
        __typeof__(lst1) _czl = lst1; \
        while (_czl->next) { \
            _czl = _czl->next; \
        } \
        _czl->next = lst2; \
        lst2->prev = _czl; \
    } else { \
        lst1 = lst2; \
    } \
} while (0)

#define list_length(lst, length) do { \
    length = 0; \
    __typeof__(lst) _czl = lst; \
    while (_czl) { \
        length++; \
        _czl = _czl->next; \
    } \
} while (0)

#define list_foreach(lst, node) \
    for (node = lst; node; node = node->next)

#define list_delete(lst, node) do { \
    if (lst == node) { \
        lst = lst->next; \
        if (lst) { \
            lst->prev = NULL; \
        } \
    } else { \
        if (node->prev) { \
            node->prev->next = node->next; \
        } \
        if (node->next) { \
            node->next->prev = node->prev; \
        } \
    } \
} while (0)

#endif
