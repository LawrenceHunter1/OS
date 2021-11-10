#include "print.h"

void kernel_main() {
    print_clear();
    print_set_colour(PRINT_COLOR_YELLOW, PRINT_COLOR_BLACK);
    print_str("Hello world!");
}