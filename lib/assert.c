#include "cz.h"
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
    fprintf(output, "\n");
    fprintf(output, "#define cz_assert(cond) do {\\\n");
    fprintf(output, "  if (!(cond)) {\\\n");
    fprintf(output, "    fprintf(stderr, \"[CZAR] ASSERTION failed at %%s:%%d: %%s\\n\", __FILE__, __LINE__, #cond);\\\n");
    fprintf(output, "    abort();\\\n");
    fprintf(output, "  }\\\n");
    fprintf(output, "} while (0)\\\n");
    fprintf(output, "\\\n");
}
