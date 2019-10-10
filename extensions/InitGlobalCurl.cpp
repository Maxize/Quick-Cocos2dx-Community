#include "InitGlobalCurl.h"

std::mutex **mutexArray = nullptr;
bool isCurlInited = false;

void crypto_lock_cb(int mode, int type, const char *file, int line)
{
    if(mode & CRYPTO_LOCK) {
        mutexArray[type]->lock();
    } else {
        mutexArray[type]->unlock();
    }
}

void InitGlobleCurl()
{
    // 官方强烈建议自己手动初始化，即使不调用， easy_init 也会自动调用
    // init curl global once
    // if (!isCurlInited) {
    //     curl_global_init(CURL_GLOBAL_ALL);
    //     isCurlInited = true;
    // }
    // HTTPS thread safe for OpenSSL
    if (!CRYPTO_get_locking_callback()) {
        mutexArray = (std::mutex **)OPENSSL_malloc(CRYPTO_num_locks() * sizeof(std::mutex *));
        for(int i = 0; i < CRYPTO_num_locks(); i++) {
            mutexArray[i] = new std::mutex;
        }
        CRYPTO_set_locking_callback(crypto_lock_cb);
    }
}
