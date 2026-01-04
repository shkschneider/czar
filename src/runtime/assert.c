#include "assert.h"

void runtime_emit_assert(FILE* output) {
    if (!output) {
        return ;
    }
    fprintf(output, "#include <stdlib.h>\n");
    fprintf(output, "#include <stdio.h>\n");
    fprintf(output, "#include <stdint.h>\n");
    fprintf(output, "#include <stdbool.h>\n");
    fprintf(output, "#include <assert.h>\n");
    fprintf(output, "#include <stdarg.h>\n");
    fprintf(output, "#include <string.h>\n");
    fprintf(output, "#define ASSERT(cond) do { if (!(cond)) { fprintf(stderr, \"[CZAR] ASSERTION failed at %%s:%%d: %%s\\n\", __FILE__, __LINE__, #cond); abort(); } } while (0)\n\n");
}
