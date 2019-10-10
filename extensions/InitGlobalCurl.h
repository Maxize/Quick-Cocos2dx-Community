#ifndef __InitGlobalCurl__
#define __InitGlobalCurl__
#include <mutex>
#include <curl/curl.h>
#include "openssl/crypto.h"

void crypto_lock_cb(int mode, int type, const char *file, int line);

void InitGlobleCurl();

#endif
