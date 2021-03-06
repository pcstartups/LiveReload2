
#ifndef LiveReload_Console_h
#define LiveReload_Console_h

#include "eventbus.h"

EVENTBUS_DECLARE_EVENT(console_message_added_event);

void console_init();

void console_put(const char *text);

void console_printf(const char *format, ...);

void console_dump();

const char *console_get();

#endif
