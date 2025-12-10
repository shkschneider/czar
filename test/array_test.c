#include <stdio.h>
#include <stdlib.h>

#include "../cz_array.h"
#include "../cz_test.h"

typedef struct node_s {
    int value;
    struct node_s* next;
} Node;

Node* node_new(int value) {
    Node* n = malloc(sizeof(Node));
    n->value = value;
    n->next = NULL;
    return n;
}

int main(void) {
    Node* list = NULL;
    
    // Test array_append
    Node* n1 = node_new(1);
    Node* n2 = node_new(2);
    Node* n3 = node_new(3);
    
    array_append(list, n1);
    assert(list == n1);
    
    array_append(list, n2);
    assert(list->next == n2);
    
    array_append(list, n3);
    assert(list->next->next == n3);
    
    // Test array_length
    size_t len;
    array_length(list, len);
    assert(len == 3);
    
    // Test array_foreach
    int sum = 0;
    Node* item;
    array_foreach(list, item) {
        sum += item->value;
    }
    assert(sum == 6); // 1 + 2 + 3
    
    // Test array_prepend
    Node* n0 = node_new(0);
    array_prepend(list, n0);
    assert(list == n0);
    assert(list->value == 0);
    
    array_length(list, len);
    assert(len == 4);
    
    // Test array_last
    Node* last;
    array_last(list, last);
    assert(last->value == 3);
    
    // Clean up
    Node* current = list;
    while (current) {
        Node* next = current->next;
        free(current);
        current = next;
    }
    
    return 0;
}
