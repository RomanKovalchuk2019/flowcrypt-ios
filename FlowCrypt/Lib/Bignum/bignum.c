#ifdef __arm64__
#include "gmp.h"
#endif
#include <stdio.h>

const char* c_gmp_mod_pow(const char* base, const char* exponent, const char* modulo) {
#ifdef __arm64__
    mpz_t mpz_base, mpz_exponent, mpz_modulo, mpz_result;
    mpz_inits (mpz_base, mpz_exponent, mpz_modulo, mpz_result, NULL);
    if (mpz_set_str (mpz_base, base, 10) != 0) {
        printf("Invalid base bigint");
        return "";
    }
    if (mpz_set_str (mpz_exponent, exponent, 10) != 0) {
        printf("Invalid base bigint");
        return "";
    }
    if (mpz_set_str (mpz_modulo, modulo, 10) != 0) {
        printf("Invalid base bigint");
        return "";
    }
    // mpz_result = mpz_base ^ mpz_exponent mod mpz_modulo
    mpz_powm (mpz_result, mpz_base, mpz_exponent, mpz_modulo);
    return mpz_get_str (NULL, 10, mpz_result);
#else
    printf("c_gmp_mod_pow is not supported on this architecture");
    return "";
#endif
}
