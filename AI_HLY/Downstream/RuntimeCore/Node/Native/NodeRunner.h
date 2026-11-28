#ifndef HanlinNodeRunner_h
#define HanlinNodeRunner_h

#ifdef __cplusplus
extern "C" {
#endif

int HanlinNodeStart(const char *argumentsJSON);
int HanlinNodeDidExit(void);

#ifdef __cplusplus
}
#endif

#endif
