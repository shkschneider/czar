#include <stdio.h>
#include <stdlib.h>

#include "../cz_list.h"
#include "../cz_test.h"

typedef struct dnode_s {
    int value;
    struct dnode_s* next;
    struct dnode_s* prev;
} DNode;

DNode* dnode_new(int value) {
    DNode* n = malloc(sizeof(DNode));
    n->value = value;
    n->next = NULL;
    n->prev = NULL;
    return n;
}

int main(void) {
    DNode* list = NULL;
    
    // Test list_append
    DNode* n1 = dnode_new(1);
    DNode* n2 = dnode_new(2);
    DNode* n3 = dnode_new(3);
    
    list_append(list, n1);
    assert(list == n1);
    assert(list->prev == NULL);
    
    list_append(list, n2);
    assert(list->next == n2);
    assert(n2->prev == n1);
    
    list_append(list, n3);
    assert(n2->next == n3);
    assert(n3->prev == n2);
    
    // Test list_length
    size_t len;
    list_length(list, len);
    assert(len == 3);
    
    // Test list_foreach
    int sum = 0;
    DNode* item;
    list_foreach(list, item) {
        sum += item->value;
    }
    assert(sum == 6); // 1 + 2 + 3
    
    // Test list_last
    DNode* last;
    list_last(list, last);
    assert(last->value == 3);
    
    // Clean up
    DNode* current = list;
    while (current) {
        DNode* next = current->next;
        free(current);
        current = next;
    }
    
    return 0;
}
