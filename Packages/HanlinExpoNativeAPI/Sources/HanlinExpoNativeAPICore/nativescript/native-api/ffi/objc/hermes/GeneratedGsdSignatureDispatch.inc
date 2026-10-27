#ifndef NS_GENERATED_GSD_SIGNATURE_DISPATCH_INC
#define NS_GENERATED_GSD_SIGNATURE_DISPATCH_INC

#undef NS_HAS_GENERATED_SIGNATURE_GSD_DISPATCH
#define NS_HAS_GENERATED_SIGNATURE_GSD_DISPATCH 1

#include <objc/message.h>

static inline bool gsd0(GsdObjCContext& ctx) {
  using Fn = SEL (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setSelector(nativeResult);
  return true;
}

static inline bool gsd1(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd2(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd3(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd4(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd5(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd6(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd7(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd8(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsd9(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsda(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdb(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdc(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdd(GsdObjCContext& ctx) {
  using Fn = double (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  double nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsde(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdf(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdg(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdh(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdi(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdj(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdk(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdl(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdm(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdn(GsdObjCContext& ctx) {
  using Fn = float (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  float nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setDouble(static_cast<double>(nativeResult));
  return true;
}

static inline bool gsdo(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdp(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int8_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  if (!ctx.readFloat(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdr(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsds(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  float arg2{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdt(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float, uint8_t, float, float, int64_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  uint8_t arg2{};
  float arg3{};
  float arg4{};
  int64_t arg5{};
  float arg6{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  if (!ctx.readFloat(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readFloat(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdv(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float, int64_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  int64_t arg2{};
  float arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float, uint32_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  uint32_t arg2{};
  double arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdx(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, float, uint32_t, uint32_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  uint32_t arg2{};
  uint32_t arg3{};
  double arg4{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdy(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  double arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, uint8_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  uint8_t arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd10(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  uint8_t arg1{};
  id arg2{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd11(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd12(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  id arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd13(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, float, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd14(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd15(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  float arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd16(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd17(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd18(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  double arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd19(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  double arg3{};
  double arg4{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double, double, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  double arg3{};
  uint8_t arg4{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  double arg3{};
  id arg4{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  id arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  id arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  uint8_t arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, uint8_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  uint8_t arg2{};
  int32_t arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  int64_t arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, uint64_t, double, double, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  uint64_t arg2{};
  double arg3{};
  double arg4{};
  double arg5{};
  double arg6{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  if (!ctx.readDouble(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, double, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  uint8_t arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  int64_t arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, int64_t, double, double, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  int64_t arg1{};
  double arg2{};
  double arg3{};
  int32_t arg4{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, int64_t, double, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  int64_t arg1{};
  double arg2{};
  int32_t arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  uint32_t arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  SEL arg2{};
  id arg3{};
  uint8_t arg4{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd1z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, uint8_t, uint8_t, uint8_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  id arg4{};
  int64_t arg5{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd20(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd21(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd22(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd23(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd24(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int32_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  int32_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd25(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int32_t, int32_t, int32_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  int32_t arg1{};
  int32_t arg2{};
  int32_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd26(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int32_t, int32_t, int32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  int32_t arg1{};
  int32_t arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd27(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int32_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  uint8_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd28(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd29(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  if (!ctx.readBool(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, uint64_t, uint8_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint64_t arg1{};
  uint8_t arg2{};
  uint64_t arg3{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int16_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int16_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int16_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  float arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  float arg1{};
  float arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  float arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  double arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, double, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  double arg1{};
  uint8_t arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, double, uint32_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  double arg1{};
  uint32_t arg2{};
  uint8_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  double arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint8_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int16_t, uint8_t, uint8_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int16_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  uint8_t arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  int64_t arg5{};
  int64_t arg6{};
  int64_t arg7{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, int64_t, int64_t, int64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  uint64_t arg6{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  int64_t arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd2z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd30(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd31(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd32(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd33(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, int64_t, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd34(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd35(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd36(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd37(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd38(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint8_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd39(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, uint64_t, uint64_t, uint64_t, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  int64_t arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  SEL arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, double, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  double arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, double, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  double arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint64_t arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id, int64_t, int64_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  int64_t arg5{};
  int64_t arg6{};
  float arg7{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readFloat(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd3z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd40(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd41(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd42(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd43(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd44(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd45(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, int64_t, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd46(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd47(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  int64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd48(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, int64_t, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  int64_t arg1{};
  uint32_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd49(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, uint32_t, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  uint32_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, uint32_t, uint32_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  uint32_t arg2{};
  float arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, uint32_t, uint32_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  uint32_t arg2{};
  double arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, uint32_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  id arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint32_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint16_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint16_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint16_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint8_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, int16_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int16_t arg1{};
  uint8_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  double arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  int64_t arg4{};
  int64_t arg5{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  int64_t arg5{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd4z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  int64_t arg5{};
  int64_t arg6{};
  int64_t arg7{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd50(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  int64_t arg6{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd51(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd52(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd53(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd54(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, id, uint64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  double arg4{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd55(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd56(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd57(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd58(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd59(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  double arg2{};
  double arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint8_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  double arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, id, int64_t, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  int64_t arg4{};
  double arg5{};
  double arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  if (!ctx.readDouble(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, int32_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  int32_t arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd5z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd60(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd61(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd62(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd63(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd64(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd65(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd66(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  uint8_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd67(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, uint16_t, uint64_t, uint16_t, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  uint16_t arg2{};
  uint64_t arg3{};
  uint16_t arg4{};
  float arg5{};
  float arg6{};
  float arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readFloat(5, &arg5)) return false;
  if (!ctx.readFloat(6, &arg6)) return false;
  if (!ctx.readFloat(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd68(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd69(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  float arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, double, float, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  double arg2{};
  float arg3{};
  uint64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint8_t, uint8_t, uint8_t, uint64_t, uint64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  double arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  if (!ctx.readDouble(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint8_t, uint64_t, uint64_t, uint64_t, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  double arg6{};
  double arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readDouble(6, &arg6)) return false;
  if (!ctx.readDouble(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint64_t, uint64_t, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  double arg4{};
  double arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, int64_t, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  uint8_t arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint8_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd6z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd70(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd71(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd72(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd73(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd74(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd75(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd76(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd77(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd78(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd79(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, double, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  double arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  id arg2{};
  SEL arg3{};
  id arg4{};
  uint8_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSelector(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int32_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int32_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int32_t arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int32_t, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int32_t arg1{};
  uint32_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd7z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int32_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int32_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd80(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd81(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd82(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd83(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd84(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd85(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd86(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd87(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd88(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, double, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  double arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd89(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, double, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  double arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint8_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, int64_t, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  uint8_t arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  SEL arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSelector(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  double arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd8z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd90(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd91(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd92(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint32_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd93(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint32_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint32_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd94(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint16_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint16_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd95(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint16_t, uint16_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint16_t arg1{};
  uint16_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd96(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint16_t, uint16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint16_t arg1{};
  uint16_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd97(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint16_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd98(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint16_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd99(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9a(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  double arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9b(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9c(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t, double, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  double arg3{};
  double arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9d(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9e(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9f(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9g(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9h(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, int64_t, double, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  double arg4{};
  double arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9i(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9j(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9k(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9l(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t, uint64_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint8_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9m(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9n(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9o(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9p(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9q(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9r(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9s(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9t(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9u(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9v(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9w(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9x(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9y(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsd9z(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsda9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float, float, uint8_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  float arg3{};
  uint8_t arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdaa(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdab(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  double arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdac(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdad(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdae(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdaf(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t, uint8_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdag(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdah(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdai(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdaj(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, uint8_t, uint8_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdak(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, uint8_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdal(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdam(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdan(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdao(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdap(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdaq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdar(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdas(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  SEL arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSelector(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdat(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  uint8_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdau(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdav(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdaw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdax(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsday(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdaz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  id arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  SEL arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSelector(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdb9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  float arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdba(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, float, float, uint8_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  float arg3{};
  float arg4{};
  uint8_t arg5{};
  int64_t arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  if (!ctx.readFloat(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbb(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  float arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbc(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  double arg3{};
  double arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbd(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, double, double, double, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  double arg3{};
  double arg4{};
  double arg5{};
  int64_t arg6{};
  int64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readDouble(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbe(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbf(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbg(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbh(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbi(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbj(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbk(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  int64_t arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbl(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbm(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbn(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint32_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbo(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbp(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbr(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t, uint64_t, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbs(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbt(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbv(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  float arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readFloat(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint8_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbx(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdby(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdbz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, uint32_t, uint32_t, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint32_t arg4{};
  uint32_t arg5{};
  uint32_t arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, uint32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint32_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, uint64_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint64_t arg4{};
  uint8_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  float arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readFloat(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  double arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  uint8_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  uint8_t arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readBool(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdc9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  int64_t arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdca(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcb(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcc(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcd(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdce(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcf(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcg(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdch(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdci(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcj(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdck(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcl(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcm(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcn(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdco(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcp(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcr(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  uint8_t arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readBool(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcs(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  uint8_t arg6{};
  int64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readBool(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdct(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  int64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcv(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcx(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcy(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdcz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, uint8_t, int64_t, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  uint8_t arg3{};
  int64_t arg4{};
  int64_t arg5{};
  int64_t arg6{};
  int64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id, int64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  int64_t arg5{};
  id arg6{};
  int64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdd9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdda(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddb(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddc(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddd(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdde(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddf(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddg(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddh(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddi(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddj(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddk(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddl(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddm(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddn(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddo(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddp(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddr(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdds(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddt(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, float, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddv(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddx(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int32_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddy(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsddz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, uint8_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readBool(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint8_t, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  SEL arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint8_t, uint8_t, uint8_t, int64_t, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  uint8_t arg4{};
  int64_t arg5{};
  int64_t arg6{};
  uint8_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readBool(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsde9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdea(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdeb(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  SEL arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSelector(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdec(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsded(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdee(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdef(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdeg(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdeh(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  SEL arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdei(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, int64_t, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  SEL arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdej(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdek(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  double arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdel(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdem(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsden(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdeo(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdep(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdeq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsder(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdes(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, int64_t, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdet(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdeu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdev(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  double arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdew(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  double arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdex(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdey(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdez(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t, uint64_t, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  uint64_t arg3{};
  id arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  SEL arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSelector(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  SEL arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSelector(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdf9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfa(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfb(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfc(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfd(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfe(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdff(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, uint16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint16_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfg(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfh(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfi(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfj(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfk(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfl(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfm(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfn(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfo(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfp(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfr(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  uint8_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readBool(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfs(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdft(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfv(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfx(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfy(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  float arg2{};
  float arg3{};
  float arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  if (!ctx.readFloat(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdfz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  double arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg8(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdg9(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdga(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgb(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgc(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgd(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdge(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgf(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgg(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgh(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgi(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgj(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgk(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgl(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int32_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgm(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgn(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgo(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgp(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgq(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgr(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  int64_t arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgs(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  int64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readSigned(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgt(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgu(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgv(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgw(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgx(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgy(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdgz(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh0(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh1(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh2(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  if (!ctx.readSelector(0, &arg0)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh3(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh4(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, SEL, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  uint64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh5(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh6(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh7(GsdObjCContext& ctx) {
  using Fn = id (*)(id, SEL, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  id nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setObject(nativeResult);
  return true;
}

static inline bool gsdh8(GsdObjCContext& ctx) {
  using Fn = int16_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int16_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdh9(GsdObjCContext& ctx) {
  using Fn = int32_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdha(GsdObjCContext& ctx) {
  using Fn = int32_t (*)(id, SEL, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  int32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdhb(GsdObjCContext& ctx) {
  using Fn = int32_t (*)(id, SEL, int32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdhc(GsdObjCContext& ctx) {
  using Fn = int32_t (*)(id, SEL, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  int32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdhd(GsdObjCContext& ctx) {
  using Fn = int32_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  int32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdhe(GsdObjCContext& ctx) {
  using Fn = int32_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  int32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdhf(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhg(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhh(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhi(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhj(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhk(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhl(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhm(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhn(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdho(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhp(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhq(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhr(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhs(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdht(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhu(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhv(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhw(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhx(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhy(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdhz(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdi0(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdi1(GsdObjCContext& ctx) {
  using Fn = int64_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  int64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setInt64(static_cast<int64_t>(nativeResult));
  return true;
}

static inline bool gsdi2(GsdObjCContext& ctx) {
  using Fn = int8_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setInt32(static_cast<int32_t>(nativeResult));
  return true;
}

static inline bool gsdi3(GsdObjCContext& ctx) {
  using Fn = uint16_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint16_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setUInt16(static_cast<uint16_t>(nativeResult));
  return true;
}

static inline bool gsdi4(GsdObjCContext& ctx) {
  using Fn = uint16_t (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  uint16_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt16(static_cast<uint16_t>(nativeResult));
  return true;
}

static inline bool gsdi5(GsdObjCContext& ctx) {
  using Fn = uint32_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setUInt32(static_cast<uint32_t>(nativeResult));
  return true;
}

static inline bool gsdi6(GsdObjCContext& ctx) {
  using Fn = uint32_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint32_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt32(static_cast<uint32_t>(nativeResult));
  return true;
}

static inline bool gsdi7(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdi8(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdi9(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdia(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdib(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdic(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdid(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdie(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdif(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdig(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdih(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdii(GsdObjCContext& ctx) {
  using Fn = uint64_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint64_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setUInt64(static_cast<uint64_t>(nativeResult));
  return true;
}

static inline bool gsdij(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdik(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  if (!ctx.readFloat(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdil(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdim(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, float, float, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdin(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, float, float, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdio(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, float, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdip(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdiq(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdir(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdis(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  if (!ctx.readBool(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdit(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdiu(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdiv(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, int64_t, float, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  float arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdiw(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdix(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdiy(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdiz(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  double arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj0(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj1(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj2(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj3(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj4(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj5(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj6(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj7(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj8(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdj9(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdja(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjb(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjc(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjd(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdje(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjf(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjg(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjh(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdji(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjj(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjk(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjl(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, uint64_t, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjm(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjn(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, int32_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int32_t arg2{};
  int32_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjo(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjp(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjq(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjr(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjs(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjt(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdju(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjv(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjw(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjx(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjy(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdjz(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk0(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk1(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk2(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk3(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk4(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk5(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk6(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk7(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk8(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdk9(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdka(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkb(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkc(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkd(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdke(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkf(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkg(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkh(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdki(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  if (!ctx.readSelector(0, &arg0)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkj(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkk(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkl(GsdObjCContext& ctx) {
  using Fn = uint8_t (*)(id, SEL, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  uint8_t nativeResult{};
  ctx.invokeNative([&]() {
    nativeResult = fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setBool(nativeResult != 0);
  return true;
}

static inline bool gsdkm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkn(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  if (!ctx.readFloat(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdko(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  float arg2{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, float, uint8_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  float arg1{};
  uint8_t arg2{};
  float arg3{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdks(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  double arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkt(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  uint8_t arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdku(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  int64_t arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkv(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  id arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkw(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, float, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  float arg0{};
  id arg1{};
  if (!ctx.readFloat(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkx(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  if (!ctx.readDouble(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdky(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  float arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdkz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, double, double, double, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  double arg2{};
  double arg3{};
  int64_t arg4{};
  int64_t arg5{};
  id arg6{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, double, int32_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  int32_t arg2{};
  int32_t arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  int64_t arg2{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, double, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  double arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  uint8_t arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  int64_t arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  uint64_t arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdl9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  double arg0{};
  id arg1{};
  if (!ctx.readDouble(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdla(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlb(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdld(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, uint8_t, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  uint8_t arg2{};
  uint8_t arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdle(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlf(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int32_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  int32_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlg(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int32_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int32_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlh(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  if (!ctx.readBool(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdli(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint8_t arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  int64_t arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlk(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  uint64_t arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdll(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint8_t arg0{};
  id arg1{};
  if (!ctx.readBool(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdln(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int16_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int16_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlo(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  if (!ctx.readSigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  float arg1{};
  float arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, float, float, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  float arg1{};
  float arg2{};
  float arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readFloat(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  double arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdls(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint8_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlt(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlu(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlv(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlw(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, int64_t, id, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  int64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  uint64_t arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlx(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdly(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t, int64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdlz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t, int64_t, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t, int64_t, id, uint64_t, uint64_t, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  int64_t arg6{};
  uint64_t arg7{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readSigned(6, &arg6)) return false;
  if (!ctx.readUnsigned(7, &arg7)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdm9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdma(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmb(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, int64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  int64_t arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmd(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdme(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint32_t, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint32_t arg0{};
  uint32_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmf(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint16_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint16_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmg(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint16_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint16_t arg0{};
  uint8_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmh(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmi(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint8_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  int64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmk(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdml(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmn(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmo(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, uint64_t, uint64_t, id, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, id, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, id, uint64_t, id, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  id arg5{};
  uint64_t arg6{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdms(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmt(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  uint64_t arg0{};
  id arg1{};
  if (!ctx.readUnsigned(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmu(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmv(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmw(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmx(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, double, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmy(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdmz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdn9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdna(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnb(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnd(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdne(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnf(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, float, float, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  float arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdng(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnh(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdni(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnk(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnl(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id, uint64_t, id, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnn(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdno(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdns(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnt(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint64_t, id, uint64_t, uint64_t, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  id arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  uint64_t arg6{};
  uint64_t arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  if (!ctx.readUnsigned(7, &arg7)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnu(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnv(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnw(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnx(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdny(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdnz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t, uint64_t, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  uint64_t arg4{};
  uint64_t arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  uint64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdo9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoa(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdob(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdod(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoe(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdof(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  uint64_t arg4{};
  int64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readUnsigned(4, &arg4)) return false;
  if (!ctx.readSigned(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdog(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoh(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, uint64_t, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  uint64_t arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readUnsigned(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoi(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdok(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdol(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdom(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdon(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  uint64_t arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readUnsigned(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoo(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdop(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdor(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdos(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdot(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, double, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdou(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdov(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int32_t, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int32_t arg1{};
  float arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readFloat(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdow(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdox(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoy(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdoz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  id arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdp9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint32_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpa(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint16_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint16_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpb(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpd(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpe(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpf(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int32_t, int32_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int32_t arg2{};
  int32_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpg(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdph(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpi(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpk(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  int64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpl(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  SEL arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSelector(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpn(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpo(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdps(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpt(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpu(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpv(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpw(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpx(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, double, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  double arg2{};
  uint8_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpy(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdpz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t, int64_t, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  int64_t arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readSigned(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint64_t arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdq9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqa(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  double arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readDouble(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqb(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqd(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqe(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqf(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  id arg5{};
  id arg6{};
  id arg7{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  if (!ctx.readObject(5, &arg5)) return false;
  if (!ctx.readObject(6, &arg6)) return false;
  if (!ctx.readObject(7, &arg7)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqg(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqh(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqi(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqk(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdql(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqn(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqo(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqs(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqt(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  id arg3{};
  id arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqu(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  uint64_t arg2{};
  uint8_t arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readUnsigned(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqv(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqw(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  SEL arg1{};
  id arg2{};
  id arg3{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSelector(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqx(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  if (!ctx.readObject(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqy(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, float);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  float arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readFloat(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdqz(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  double arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readDouble(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr0(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint8_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readBool(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr1(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr2(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr3(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr4(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, int64_t, id, id, int64_t, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  int64_t arg1{};
  id arg2{};
  id arg3{};
  int64_t arg4{};
  double arg5{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readSigned(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  if (!ctx.readSigned(4, &arg4)) return false;
  if (!ctx.readDouble(5, &arg5)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4, arg5);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr5(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr6(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, uint64_t, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  uint64_t arg1{};
  uint8_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readUnsigned(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr7(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr8(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdr9(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdra(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrb(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, int64_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  int64_t arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readSigned(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrc(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrd(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdre(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrf(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrg(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrh(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, id, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  id arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readObject(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdri(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  if (!ctx.readSelector(0, &arg0)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrj(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrk(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, double);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  double arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrl(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, double, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  double arg2{};
  id arg3{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readDouble(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrm(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  uint8_t arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrn(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  uint8_t arg2{};
  id arg3{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readBool(2, &arg2)) return false;
  if (!ctx.readObject(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdro(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrp(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, id, uint64_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  uint64_t arg3{};
  id arg4{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readUnsigned(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrq(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrr(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, id, uint8_t);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  uint8_t arg3{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3);
  });
  ctx.setVoid();
  return true;
}

static inline bool gsdrs(GsdObjCContext& ctx) {
  using Fn = void (*)(id, SEL, SEL, id, id, uint8_t, id);
  auto fn = reinterpret_cast<Fn>(objc_msgSend);
  SEL arg0{};
  id arg1{};
  id arg2{};
  uint8_t arg3{};
  id arg4{};
  if (!ctx.readSelector(0, &arg0)) return false;
  if (!ctx.readObject(1, &arg1)) return false;
  if (!ctx.readObject(2, &arg2)) return false;
  if (!ctx.readBool(3, &arg3)) return false;
  if (!ctx.readObject(4, &arg4)) return false;
  ctx.invokeNative([&]() {
    fn(ctx.self, ctx.selector, arg0, arg1, arg2, arg3, arg4);
  });
  ctx.setVoid();
  return true;
}

inline constexpr ObjCGsdDispatchEntry kGeneratedObjCGsdDispatchEntries[] = {
    {0, nullptr},
    {0x000492b255f54e6aULL, &gsdkq},
    {0x001a7ca13ff28abeULL, &gsdhg},
    {0x005f477c05a9d4abULL, &gsdgr},
    {0x00950eb48477d23bULL, &gsd9j},
    {0x00a81453cddfc7cfULL, &gsdmj},
    {0x01e18563feceefc2ULL, &gsd50},
    {0x0208b7d9405a0722ULL, &gsdmx},
    {0x024e787c7027da77ULL, &gsd1y},
    {0x02a18bebc1f31014ULL, &gsdin},
    {0x030febb479443fccULL, &gsdmn},
    {0x0358946cb0dd8e61ULL, &gsdlt},
    {0x0362420a3ca6bf7eULL, &gsd67},
    {0x03a9a75d4f1049c6ULL, &gsdlk},
    {0x03d820e8df6f9a42ULL, &gsd79},
    {0x03ef0619e40f2d11ULL, &gsd46},
    {0x03f192e0a8ccd3f2ULL, &gsdh8},
    {0x04f47db81bfd56b0ULL, &gsd9d},
    {0x057cfbce5219d0c0ULL, &gsdmm},
    {0x05c4660f520e230fULL, &gsde0},
    {0x05c6511d856322d4ULL, &gsd47},
    {0x061cf29fc24270b2ULL, &gsd6t},
    {0x063826e21d2b2ca1ULL, &gsdhs},
    {0x064a4c2b8b42a702ULL, &gsdl4},
    {0x065d188190eb7373ULL, &gsd2i},
    {0x072c3398876a9fdcULL, &gsdae},
    {0x07eb919349b252d4ULL, &gsd5k},
    {0x08be2fb44412c6ffULL, &gsd8a},
    {0x08d4977d70c36724ULL, &gsdmi},
    {0x08d5c7e3a6ceeef0ULL, &gsdl6},
    {0x0902b6ff96b9d06dULL, &gsd2m},
    {0x0a00700563d7f604ULL, &gsd72},
    {0x0a10ef9275605c3aULL, &gsd3g},
    {0x0aabba25fdb002d8ULL, &gsd4n},
    {0x0b5c990c39b9ddaeULL, &gsdmu},
    {0x0b71632fdff8cc88ULL, &gsdnm},
    {0x0bfb857c1a62f7f7ULL, &gsdkz},
    {0x0c6954c133cd3c47ULL, &gsdrr},
    {0x0c714a6cdcb09405ULL, &gsdc1},
    {0x0cb071e665f48f40ULL, &gsdhj},
    {0x0d6d81abe6d59af6ULL, &gsdml},
    {0x0d996d63b0681444ULL, &gsd7o},
    {0x0dceda4e3a67032bULL, &gsdl1},
    {0x0e0b7b4f35eadc19ULL, &gsdm8},
    {0x0ec8e61c445d05e6ULL, &gsd3k},
    {0x0ff2fd7127f92b12ULL, &gsd8z},
    {0x10180f4859db1a74ULL, &gsd9m},
    {0x10de9e09524d57a7ULL, &gsdl},
    {0x111bb48953b610ddULL, &gsd4y},
    {0x115cb211893cb666ULL, &gsdbq},
    {0x117c1d24da23c575ULL, &gsd1r},
    {0x12155108e2b64f99ULL, &gsd1v},
    {0x1264fe8efbe6b9d6ULL, &gsdr},
    {0x128b361848c197beULL, &gsdd5},
    {0x12e237cfe05272ecULL, &gsdou},
    {0x12f0772a68901513ULL, &gsd9e},
    {0x138c51e8c7711435ULL, &gsd81},
    {0x13aea763a2e170e5ULL, &gsdm2},
    {0x13b19dba4908c2b6ULL, &gsdmg},
    {0x13c10aa741527532ULL, &gsd69},
    {0x141c7fa9def7020eULL, &gsd6p},
    {0x15a51f39e6dc1d26ULL, &gsdl5},
    {0x1654aced70879434ULL, &gsdax},
    {0x16f2d09c2bc1983bULL, &gsd31},
    {0x17281b665ad2fa2aULL, &gsdqf},
    {0x176f16561e7e10fcULL, &gsdik},
    {0x17f749890d35d5ebULL, &gsd2},
    {0x196b1450867096f7ULL, &gsdee},
    {0x19da656900a62c7fULL, &gsdif},
    {0x1a589ab5c1de3baeULL, &gsd9n},
    {0x1b0d856c1ef7da17ULL, &gsdo},
    {0x1b31b558d90ccabdULL, &gsdiu},
    {0x1b982ce1b524799fULL, &gsd1b},
    {0x1c3c4f771e629cbfULL, &gsdrn},
    {0x1d34f590e30cc75bULL, &gsd3f},
    {0x1d4fc38742e66b29ULL, &gsd15},
    {0x1d855806111af2a9ULL, &gsdbm},
    {0x1edb2ec1a5dda77aULL, &gsdh0},
    {0x1f0b665701d9bea2ULL, &gsdli},
    {0x1f0dbc2b0f61a432ULL, &gsdp1},
    {0x1f0ea518af819efeULL, &gsd8d},
    {0x1f364282a0180e15ULL, &gsd12},
    {0x1f758274619e31a5ULL, &gsd21},
    {0x20236175305f2623ULL, &gsdlz},
    {0x207592452f4d199cULL, &gsd3m},
    {0x212a0456806735adULL, &gsddu},
    {0x21f464136a7a098bULL, &gsd32},
    {0x221818d0df75f3d0ULL, &gsdi1},
    {0x227212bacc5bc314ULL, &gsd9k},
    {0x22b85ff0059cc6e7ULL, &gsdkb},
    {0x22d38373d2f4cb44ULL, &gsdib},
    {0x239dc22358d1fe2dULL, &gsd8r},
    {0x259901648ea183cdULL, &gsd4f},
    {0x25b4844bd67b59f2ULL, &gsdjz},
    {0x25b9bd13d53c824fULL, &gsd48},
    {0x260444fcf8592176ULL, &gsd22},
    {0x261f1f183133639dULL, &gsdlx},
    {0x27fd3cefdfde62efULL, &gsdgl},
    {0x28725124e46e53d8ULL, &gsda9},
    {0x2907ac22e65d8927ULL, &gsdh7},
    {0x291c7ff5a8291489ULL, &gsdbp},
    {0x2a411ee6b822bf12ULL, &gsd3},
    {0x2ab48cfadcf13d2eULL, &gsda},
    {0x2b803755e8b8c612ULL, &gsd7q},
    {0x2bfe62be5e9e92cfULL, &gsdle},
    {0x2c0182713db1ae05ULL, &gsdh4},
    {0x2c5cd489d9acdcbbULL, &gsdhc},
    {0x2d0db48b9eb72274ULL, &gsd52},
    {0x2dee959e454942acULL, &gsd1m},
    {0x2e2c6ec88f600588ULL, &gsdkn},
    {0x2e3066a105be3b3fULL, &gsd2v},
    {0x2e3aef2a325b2c7fULL, &gsdqp},
    {0x2e9e1ae3186a8565ULL, &gsd83},
    {0x2f049bda94072536ULL, &gsdhq},
    {0x2f0e452fb879d825ULL, &gsdoc},
    {0x2f95ada158f427a5ULL, &gsd8c},
    {0x308ad2693fb92978ULL, &gsdlb},
    {0x30a654914bc81671ULL, &gsd8g},
    {0x3157f8347b42530aULL, &gsd4g},
    {0x31ab65f3c1d2e6fdULL, &gsdbj},
    {0x336f3c6d4f58f9cdULL, &gsd6y},
    {0x3448c9b376d80edcULL, &gsdc0},
    {0x34633699f269e897ULL, &gsd6c},
    {0x3487c6af473427d1ULL, &gsd16},
    {0x34d062d1a4b3ce1dULL, &gsdv},
    {0x34dc58503d7b2483ULL, &gsd1},
    {0x36324fcb1d4400a7ULL, &gsdks},
    {0x36a1cecc310363deULL, &gsdgm},
    {0x36b13abdb9ca273bULL, &gsd27},
    {0x36e0696ac369785dULL, &gsdmv},
    {0x3702275ddc61e9f0ULL, &gsdim},
    {0x374a87e1a0a55c70ULL, &gsdjj},
    {0x37e50b9a2f4c296bULL, &gsd24},
    {0x39105a7ac29f86e5ULL, &gsdfv},
    {0x39142ec4deb43054ULL, &gsdfu},
    {0x394579d8bec553b0ULL, &gsd1p},
    {0x399e63670dc7d489ULL, &gsd7n},
    {0x39b3657cd7055e6dULL, &gsdk0},
    {0x3a79bdaaa4492ea8ULL, &gsdq4},
    {0x3ad37b820d015d7bULL, &gsd55},
    {0x3b533b6dff654785ULL, &gsdnk},
    {0x3bbc292e7e5af0f0ULL, &gsdit},
    {0x3bcac21045f12740ULL, &gsdir},
    {0x3bfa52c2651fbdaaULL, &gsdc5},
    {0x3c8db58a920040b0ULL, &gsd1l},
    {0x3cd22c028c180c77ULL, &gsdlg},
    {0x3d3e730e75940072ULL, &gsdhk},
    {0x3d49144052c3a1a5ULL, &gsdeh},
    {0x3d6aa9536acf8047ULL, &gsdk9},
    {0x3da09b8d1835944dULL, &gsdl2},
    {0x3dad8d5e60e75fa2ULL, &gsd5p},
    {0x3e7f6513892fbb90ULL, &gsdpy},
    {0x3ea75654800df7cfULL, &gsdlf},
    {0x3f01059b0ca2436aULL, &gsdo2},
    {0x416f662fde56ada8ULL, &gsd8w},
    {0x41b7062c5517665cULL, &gsd8v},
    {0x425b88073e8510e0ULL, &gsd3u},
    {0x439bce5635416becULL, &gsd8b},
    {0x4491a82f9bf06dd2ULL, &gsd3l},
    {0x44cfcff2a3c7b401ULL, &gsd61},
    {0x45924e7f137f48baULL, &gsddf},
    {0x46af288cc11dc21aULL, &gsds},
    {0x46b947a324cec2cbULL, &gsdj1},
    {0x46d021de6edc582dULL, &gsd3w},
    {0x4803807c72092a72ULL, &gsd2g},
    {0x4815d1395109ad89ULL, &gsdcm},
    {0x4844ea9f8bb17ed5ULL, &gsdc6},
    {0x48996bfc8d065a9eULL, &gsdlc},
    {0x4936cfa5bcda4994ULL, &gsd1g},
    {0x494db497c3590cebULL, &gsdky},
    {0x498e5f1b551ac31dULL, &gsdbv},
    {0x4a070343c343deebULL, &gsd36},
    {0x4a5dae3e2d56b65cULL, &gsd2t},
    {0x4b8c3749cbfb6e94ULL, &gsdo},
    {0x4b94eb107617e7d3ULL, &gsd5c},
    {0x4c8a89e08ae35f6dULL, &gsdno},
    {0x4ca2baaa378f869eULL, &gsd2z},
    {0x4cdc2ff071d8ccb0ULL, &gsdkr},
    {0x4d36479d56e95999ULL, &gsd9x},
    {0x4e3999644f7ea6bfULL, &gsd2a},
    {0x4e46ee446f422394ULL, &gsdoz},
    {0x4f9c811f10b43d3aULL, &gsdr4},
    {0x502475e0bf234687ULL, &gsdlh},
    {0x50a2487d60f9c0b0ULL, &gsdjd},
    {0x5131d06e0e49c3f1ULL, &gsd8q},
    {0x51b4ad34110e90ddULL, &gsd89},
    {0x51f0e2527243ff9eULL, &gsdmd},
    {0x524d743934118a67ULL, &gsd4j},
    {0x5309dab03e31bd76ULL, &gsdno},
    {0x533998d4fcbcf9ccULL, &gsdat},
    {0x540fdda531854c6eULL, &gsdon},
    {0x5472a4351a607234ULL, &gsdgf},
    {0x54984f8414177985ULL, &gsd7v},
    {0x54cd3ace17264d03ULL, &gsdls},
    {0x55b9e9e164146096ULL, &gsd3r},
    {0x567757aa5fa95a05ULL, &gsdjf},
    {0x568cbf179a4ccde1ULL, &gsdbd},
    {0x568d92ffa6aebe2fULL, &gsd4m},
    {0x571e53c358236f9bULL, &gsdo7},
    {0x57a30a9e5088a1e9ULL, &gsd39},
    {0x57c0fe6c398759b4ULL, &gsdnb},
    {0x58378e4d5d2ef95bULL, &gsdnz},
    {0x5899fe57618afb6aULL, &gsd8},
    {0x58fb6757dbf3f17aULL, &gsdes},
    {0x5947abe82f1b9b14ULL, &gsdh3},
    {0x59b628f62a5772b1ULL, &gsd2j},
    {0x59ffb559372c4166ULL, &gsdnl},
    {0x5a60e3876e058c83ULL, &gsdij},
    {0x5b2dade200014cefULL, &gsd1h},
    {0x5b71cb6bdeaf7b25ULL, &gsdeu},
    {0x5bb70bb96c8d92a3ULL, &gsdo9},
    {0x5bc368fcdf581ecaULL, &gsd4b},
    {0x5bdcebebd3f52348ULL, &gsd2s},
    {0x5bef078ef8bac034ULL, &gsd9u},
    {0x5cefb04d6844dedbULL, &gsd6e},
    {0x5d1176baccdf1c4aULL, &gsddt},
    {0x5dd6a7c8688eca10ULL, &gsdq3},
    {0x5e0c8acbc7f0e4cfULL, &gsd25},
    {0x5e10a83b4208c0aeULL, &gsd86},
    {0x5e9be67c241a3cb7ULL, &gsd1d},
    {0x606403a32a1ce641ULL, &gsd7w},
    {0x60aa87751d73f296ULL, &gsdmo},
    {0x60d599a19e4528e8ULL, &gsdrs},
    {0x60ea21f8f8ba16bcULL, &gsdqh},
    {0x60f4c1e8ce187b8eULL, &gsdix},
    {0x614f67e5ea255924ULL, &gsdri},
    {0x61809c8fabea59f2ULL, &gsdnd},
    {0x62d2dbd245a6c319ULL, &gsd8h},
    {0x62f0cc965457872aULL, &gsdcr},
    {0x6305f892e7c36038ULL, &gsd4a},
    {0x630b089462f027d8ULL, &gsdk6},
    {0x632f1943925eadcbULL, &gsd38},
    {0x63d9937f0a5eac51ULL, &gsd6a},
    {0x64999843f64d5760ULL, &gsdfb},
    {0x64b3a3a35f20a77cULL, &gsdpe},
    {0x653cfc790ad06ff3ULL, &gsdof},
    {0x65a9a4cf8dd44d24ULL, &gsdas},
    {0x65ade9afc789c80eULL, &gsdew},
    {0x66e5555b9c8d372bULL, &gsd5r},
    {0x6706dbf3848d07b2ULL, &gsdb1},
    {0x6753ecc1646d95c6ULL, &gsdaj},
    {0x67b273439edf066eULL, &gsdfj},
    {0x67e7b3d1c1d552e2ULL, &gsdg3},
    {0x68b2a2ceaca35f45ULL, &gsdp4},
    {0x690c927e00782ee0ULL, &gsdi4},
    {0x69be4bc127973b8eULL, &gsdft},
    {0x69eb9c1a05bf9377ULL, &gsdm0},
    {0x6a18f9ccd2e03f6aULL, &gsdiw},
    {0x6af07ec9e67354b9ULL, &gsdbk},
    {0x6afc28ff9f7b59c3ULL, &gsdnw},
    {0x6afc3f0dbe5293e8ULL, &gsdia},
    {0x6b02faa80b3ebbf2ULL, &gsd2h},
    {0x6b74df0a020209ffULL, &gsde5},
    {0x6b8fe6a0ff3174a8ULL, &gsdfl},
    {0x6bd18c527cc181b3ULL, &gsd3c},
    {0x6c1738a7a9f299c5ULL, &gsdla},
    {0x6c66767720d882ccULL, &gsd6},
    {0x6d4c79a39ac5b015ULL, &gsdkk},
    {0x6d58e828919189b4ULL, &gsd49},
    {0x6d6f514a534070f7ULL, &gsdll},
    {0x6d836ec142c7f59eULL, &gsd6g},
    {0x6dcd204e79a8b82dULL, &gsdmw},
    {0x6e630c16b5eb1e3dULL, &gsd8o},
    {0x6e6745a50cccf76fULL, &gsd29},
    {0x6edcd705f76f7a70ULL, &gsd3t},
    {0x6efa96fcd2d95930ULL, &gsdiz},
    {0x6ffa53f1852e3914ULL, &gsdfs},
    {0x70645dbf5cb942e6ULL, &gsdpm},
    {0x70775b4a96543362ULL, &gsdki},
    {0x72ff18fd9fd04553ULL, &gsd2q},
    {0x7363068cc3c43c48ULL, &gsdpd},
    {0x745a6348c4d2224bULL, &gsd5},
    {0x7460f627fe72f647ULL, &gsdah},
    {0x74719c5f82e53116ULL, &gsdz},
    {0x74d0a519ec590f17ULL, &gsd8l},
    {0x755e0d868518a4c5ULL, &gsd6n},
    {0x75641cf0ccf9f1d9ULL, &gsd58},
    {0x7592c819bac415f8ULL, &gsd9c},
    {0x762c759db0c5880aULL, &gsdaw},
    {0x775ca9ed00f148c8ULL, &gsd35},
    {0x779c8506e149a6e2ULL, &gsdm1},
    {0x77f4148a43903ff9ULL, &gsdrk},
    {0x7804947629d2ed35ULL, &gsd23},
    {0x7853955abc83e6f8ULL, &gsdiv},
    {0x78c0cbed8c50580bULL, &gsdq0},
    {0x78fbe4484f253b08ULL, &gsdn1},
    {0x7979620b76285be0ULL, &gsd4p},
    {0x79ab49ac66593d0bULL, &gsdnt},
    {0x7ae2736b7f351049ULL, &gsdd},
    {0x7b7b6382bd880f94ULL, &gsd96},
    {0x7be450c104157107ULL, &gsd95},
    {0x7bf1c78c38274498ULL, &gsdk},
    {0x7c0708b2d317b3caULL, &gsdw},
    {0x7c4e0237973aa953ULL, &gsd8k},
    {0x7d0568b0d34e20a0ULL, &gsdds},
    {0x7d8a2cb4e50d7963ULL, &gsdal},
    {0x7d91e2cab674dc7cULL, &gsdol},
    {0x7df89787e3c2f4edULL, &gsd4w},
    {0x7e4d660691be7b15ULL, &gsd4},
    {0x7f41ea538580d912ULL, &gsdpx},
    {0x7f7cc92697ce3196ULL, &gsdnq},
    {0x8046c31cc1d42708ULL, &gsdpf},
    {0x807be16abe7cf23eULL, &gsdp9},
    {0x808219057f978afdULL, &gsdj0},
    {0x8194b0c2e9d35598ULL, &gsdar},
    {0x81c62658ca412b75ULL, &gsdaf},
    {0x82025aedd238e653ULL, &gsdjn},
    {0x822e41b2f01d48b7ULL, &gsdmf},
    {0x82a657344f373785ULL, &gsd2k},
    {0x8330cdb9099a8a24ULL, &gsdbs},
    {0x833e3c76b80dc3e8ULL, &gsdb9},
    {0x83eadff37498fa94ULL, &gsd8t},
    {0x843ee3c3689e8488ULL, &gsd9g},
    {0x84441e2654c7fb6fULL, &gsdjo},
    {0x8445f62f8ba99e37ULL, &gsdjp},
    {0x84d9ac34ae3870e6ULL, &gsdi0},
    {0x85b5b17347bc81dfULL, &gsd18},
    {0x8653a59886b5d5d9ULL, &gsd2u},
    {0x86e906978e4687d1ULL, &gsd4t},
    {0x8800813cccc05f30ULL, &gsdio},
    {0x881f805cfbf5629cULL, &gsdjr},
    {0x88b705ac4e5ef8c3ULL, &gsd3q},
    {0x8922a1a29b1b91a4ULL, &gsdrj},
    {0x893db1e5895c5929ULL, &gsdot},
    {0x8947ec62ba6a6b79ULL, &gsd2r},
    {0x8a7881fd2f3183abULL, &gsd10},
    {0x8afe4654d84e5f4bULL, &gsdpz},
    {0x8aff2b05fe3472dcULL, &gsdlj},
    {0x8b1235bfcf183136ULL, &gsdnc},
    {0x8b2a8e3a915ba58eULL, &gsdd3},
    {0x8b4ef9abe2588415ULL, &gsdly},
    {0x8b8c32b5f02fdcacULL, &gsdlu},
    {0x8c45267142923454ULL, &gsd4q},
    {0x8c88f5defb4eef79ULL, &gsdak},
    {0x8d0dd0991618f514ULL, &gsdna},
    {0x8dad9fc6a750662dULL, &gsdis},
    {0x8dafba192b064f90ULL, &gsdoh},
    {0x8e1625082747fc64ULL, &gsdgn},
    {0x8e43ca667f80d3e9ULL, &gsdhv},
    {0x8e63bdbf7c39c808ULL, &gsdp2},
    {0x8e704e37f456709aULL, &gsd7m},
    {0x8ee566f0a0e4eb74ULL, &gsdn},
    {0x8f6d032463d351e3ULL, &gsd54},
    {0x8f7c2bd374345b78ULL, &gsd1o},
    {0x9063b369b27f7b5aULL, &gsd4u},
    {0x90e57b3528ef53f1ULL, &gsdox},
    {0x91084fb532593359ULL, &gsdh2},
    {0x91d8f24396e18c9eULL, &gsd20},
    {0x92a35b3f9d1334b9ULL, &gsdai},
    {0x934390b19c3e00a5ULL, &gsd80},
    {0x9355a018eb4856eeULL, &gsdmb},
    {0x938146fdce7ed417ULL, &gsdx},
    {0x9435b4d2dc6dfc55ULL, &gsdpc},
    {0x957342137f1b4c5dULL, &gsdbc},
    {0x958c761f5758cbfdULL, &gsd92},
    {0x9631e2d2d8e52530ULL, &gsdm6},
    {0x9748bb6abbca8cd8ULL, &gsdba},
    {0x976355d9646c28e5ULL, &gsd5l},
    {0x978390235db97ca5ULL, &gsd3j},
    {0x97b1ce6c78b1f052ULL, &gsdcg},
    {0x97c8f5ec5b94fed2ULL, &gsdbw},
    {0x98d7c0a043df0d05ULL, &gsdh5},
    {0x991e0fb86bfca890ULL, &gsd33},
    {0x99f29ede08ff18caULL, &gsd70},
    {0x9a36be06eb797cceULL, &gsdfy},
    {0x9a89a616952e21b3ULL, &gsdkl},
    {0x9b223e068b08f7c5ULL, &gsd2e},
    {0x9b54ec71fb93ae89ULL, &gsd66},
    {0x9b993ce227d868adULL, &gsdl3},
    {0x9bee457b9c542d44ULL, &gsdpa},
    {0x9c7bb556748597afULL, &gsdkt},
    {0x9c8545f060624977ULL, &gsd5s},
    {0x9cd27b6c133257d6ULL, &gsdc4},
    {0x9d6616f13dfbf20dULL, &gsdb0},
    {0x9ec1467718bb3a8fULL, &gsdbo},
    {0x9f1bc45a8ae90b78ULL, &gsd2l},
    {0x9fe53a22aaedb450ULL, &gsdmt},
    {0xa024284b14a4bfe8ULL, &gsd4d},
    {0xa06074dde93adbc0ULL, &gsd8i},
    {0xa0640b6cea465cacULL, &gsda8},
    {0xa08b9b563823a5faULL, &gsd5a},
    {0xa0aaa61ba1b61f3bULL, &gsdip},
    {0xa0c7499511510ef4ULL, &gsdi},
    {0xa0cab955b46546adULL, &gsd4u},
    {0xa0cebd975d064585ULL, &gsdq},
    {0xa106d4b2a539f467ULL, &gsd4c},
    {0xa123c62e8e2ca039ULL, &gsdji},
    {0xa168eb06d28b5521ULL, &gsd4l},
    {0xa189439c62f5e056ULL, &gsd6f},
    {0xa26d7b4df44956eeULL, &gsdev},
    {0xa2f4426cf56d98e2ULL, &gsd9o},
    {0xa320560036a8a50fULL, &gsd1i},
    {0xa388a92ab8d5900cULL, &gsdkx},
    {0xa3a4ee7b5b282a1eULL, &gsdmr},
    {0xa3adda1c5c0a00f2ULL, &gsdjh},
    {0xa47e7345e5d28d64ULL, &gsdbg},
    {0xa47f21693d6810a0ULL, &gsdap},
    {0xa52274840fad9832ULL, &gsda5},
    {0xa547dd4d003bf7d3ULL, &gsd4r},
    {0xa549450a11854ad1ULL, &gsdnx},
    {0xa67d1a9a3d38627bULL, &gsdf0},
    {0xa6f63021b7f19c65ULL, &gsdhb},
    {0xa741bf4c1d0da55eULL, &gsdov},
    {0xa7de35a7e7ec7364ULL, &gsdi5},
    {0xa7ef47690e055c82ULL, &gsdaz},
    {0xa80ffed4dce94d52ULL, &gsdad},
    {0xa85f5970860ee5a0ULL, &gsd11},
    {0xa88a27524bf319d7ULL, &gsdko},
    {0xa89390a3ad804cb9ULL, &gsdg},
    {0xa9476dc3c1739261ULL, &gsd6d},
    {0xa9d56166392e318eULL, &gsdka},
    {0xaa1eb872de1640e0ULL, &gsdh1},
    {0xaa7cceaa750973c3ULL, &gsd4v},
    {0xaaac88c55bde7820ULL, &gsdf7},
    {0xaace0f33d75f3ae2ULL, &gsd8e},
    {0xab62a11713a3a6b6ULL, &gsd2n},
    {0xabcaa92c38bef4a3ULL, &gsd3o},
    {0xac2711656bb841d2ULL, &gsd1j},
    {0xac59d5169a12ae17ULL, &gsdro},
    {0xacd0beda20823782ULL, &gsdf4},
    {0xadade22d2af21975ULL, &gsd9l},
    {0xae69a97d6ae10d31ULL, &gsdei},
    {0xae81057df018d53aULL, &gsdlv},
    {0xaef73d9b73efc59aULL, &gsd9i},
    {0xaf8adfadebb3272fULL, &gsdrp},
    {0xaf8b34be798f6b08ULL, &gsd1k},
    {0xaffd78832a740d4fULL, &gsd6v},
    {0xb0134dca6c022619ULL, &gsdq1},
    {0xb076b09c334053dfULL, &gsdnu},
    {0xb0a4cf2f0137ba47ULL, &gsdy},
    {0xb0a8c4c2de905247ULL, &gsd65},
    {0xb17c55a389081a19ULL, &gsdf8},
    {0xb1849d1207c75e09ULL, &gsd1e},
    {0xb1e22f320ed28525ULL, &gsdnn},
    {0xb2391a44743617beULL, &gsdij},
    {0xb299614e11f022f9ULL, &gsdld},
    {0xb3588a8a56127a51ULL, &gsdiq},
    {0xb377cb7c1631979bULL, &gsd17},
    {0xb3dd667cdf4cad43ULL, &gsdct},
    {0xb486787dba9d2d00ULL, &gsdbr},
    {0xb5891ea2a0bf9011ULL, &gsdbn},
    {0xb73ae6d2453b9d16ULL, &gsdk8},
    {0xb74457a5d7bbec40ULL, &gsd6r},
    {0xb795c2a52ac27579ULL, &gsd5m},
    {0xb7ca0d89f124102fULL, &gsdnf},
    {0xb8a0d620acd5079fULL, &gsd2y},
    {0xb8e2600052d4c608ULL, &gsdjk},
    {0xb920510d543eb0efULL, &gsd94},
    {0xb967a9c7e4e42d3cULL, &gsd34},
    {0xb996d21c902eedb9ULL, &gsd3v},
    {0xb9e36f60b8b42d3eULL, &gsd2f},
    {0xba4377b506f2cae6ULL, &gsdag},
    {0xba531d6a9aa0b7a3ULL, &gsd4n},
    {0xba72830e4e9ff432ULL, &gsd5h},
    {0xbb14b19eb26d412eULL, &gsdhn},
    {0xbb9c00dedad0a8e7ULL, &gsdp},
    {0xbbc4698508d79215ULL, &gsd0},
    {0xbc512529d732edbfULL, &gsdrm},
    {0xbc6c164cff9fbe95ULL, &gsdj2},
    {0xbc847125e40df21eULL, &gsd7z},
    {0xbcfd52b7200483e9ULL, &gsd1t},
    {0xbd3a089cae7e09f7ULL, &gsdp3},
    {0xbd81ef19d13d0e9eULL, &gsde2},
    {0xbe2ec6d7483deb36ULL, &gsd2d},
    {0xbf149d302b8b4ea2ULL, &gsdi2},
    {0xbf7ec48412d5ab88ULL, &gsdf3},
    {0xc05cd5c5e04bf0a1ULL, &gsdkf},
    {0xc0603951d27e7e3aULL, &gsdjv},
    {0xc074ff8c9177fb5eULL, &gsd3h},
    {0xc0cc1fb0d0bda299ULL, &gsd19},
    {0xc0deb457913fa47bULL, &gsd4s},
    {0xc1548b2b1fd01887ULL, &gsd9},
    {0xc22559c4555dcb1aULL, &gsdgv},
    {0xc255d4f4f28c368bULL, &gsd97},
    {0xc2946dfe8c86ce8dULL, &gsd8y},
    {0xc2f4d1644d72ed1fULL, &gsd1u},
    {0xc2fbd63a3d6c272aULL, &gsdr2},
    {0xc33b41a233cf4a7eULL, &gsde},
    {0xc4a53884a7bc2761ULL, &gsd2p},
    {0xc54942d96988f016ULL, &gsdmk},
    {0xc5f4bdf314526d70ULL, &gsd4x},
    {0xc6831966080af570ULL, &gsdq2},
    {0xc690e8725d1ad918ULL, &gsdam},
    {0xc71f3ddfccc14649ULL, &gsdhw},
    {0xc7fe58e5382e4f16ULL, &gsdp0},
    {0xc854d2e2be930133ULL, &gsd93},
    {0xc8fc3c8617a418adULL, &gsdrl},
    {0xc9d503b9e0fd42fcULL, &gsdqu},
    {0xca417ad6b4a9ea71ULL, &gsdcc},
    {0xca5e1ff9c481b39bULL, &gsd4q},
    {0xca6abda4cec54920ULL, &gsd4z},
    {0xcaef439a0495d411ULL, &gsdoy},
    {0xcb1e8f093c5d9589ULL, &gsd1z},
    {0xcb4d48c6e165635aULL, &gsd51},
    {0xcc3ca23cceef27c2ULL, &gsdkw},
    {0xcd44c23e16c67d68ULL, &gsd7k},
    {0xcde53cd326761c51ULL, &gsdo4},
    {0xce2e49e115ccf385ULL, &gsd1f},
    {0xce77afc77ec09022ULL, &gsdi8},
    {0xced4fe2b82fc86f1ULL, &gsdel},
    {0xd043635fe49700d3ULL, &gsdqa},
    {0xd04aff231d53bdceULL, &gsd9h},
    {0xd09fef5ec0f972acULL, &gsd5b},
    {0xd0f0cb0de52f9e6bULL, &gsd4o},
    {0xd1bcdab3518d081dULL, &gsd86},
    {0xd20fcae1bcdbc75bULL, &gsd8u},
    {0xd21970eacb657520ULL, &gsdlr},
    {0xd2ed402df34940eeULL, &gsder},
    {0xd338f836524e3084ULL, &gsd37},
    {0xd38376309ebb80c8ULL, &gsdhd},
    {0xd38b5196e2cdb976ULL, &gsdjl},
    {0xd415dc4146dc791eULL, &gsdcb},
    {0xd430d5b150e0eb4aULL, &gsd2o},
    {0xd46044ac0c488f6bULL, &gsd3p},
    {0xd4ce8f2a51cbf483ULL, &gsd9f},
    {0xd55ccc11959670a7ULL, &gsdc2},
    {0xd66249262578d0c2ULL, &gsdfx},
    {0xd6aaf95c056fa452ULL, &gsdff},
    {0xd6cb07010be72e52ULL, &gsdt},
    {0xd86829fdb3005b0aULL, &gsdfd},
    {0xd86bf61952dd6d84ULL, &gsdlo},
    {0xd89088896d5e23c9ULL, &gsdi6},
    {0xd9e63cfa0aa85f7bULL, &gsd7x},
    {0xda0fdeda9eb411c9ULL, &gsd3s},
    {0xda89e66e856f2db1ULL, &gsd2c},
    {0xda9881eeba069d54ULL, &gsda1},
    {0xdb31159407f4e5b7ULL, &gsdln},
    {0xdb54440ee7aa3a45ULL, &gsdaq},
    {0xdb5606ef14d728e4ULL, &gsdjt},
    {0xdb5ea38b6c6664a8ULL, &gsd13},
    {0xdb8f17c9f646f032ULL, &gsd30},
    {0xdc1008baae2bec68ULL, &gsde6},
    {0xdc3e89b9b121daffULL, &gsd9p},
    {0xdcc7f151ead0c005ULL, &gsdh9},
    {0xdcf85d00dd00be09ULL, &gsd26},
    {0xdd255a0e5aa92b34ULL, &gsd88},
    {0xdd73c23d9a588707ULL, &gsdhh},
    {0xde5e9f316303d1bbULL, &gsd5f},
    {0xdedb2c52a1059d31ULL, &gsd7b},
    {0xdf72e4e4a45a2b71ULL, &gsdmh},
    {0xdff2485cd3c4e33fULL, &gsdbb},
    {0xe0379f0823ba2007ULL, &gsd8f},
    {0xe13455c1134b4bb4ULL, &gsdq6},
    {0xe14bc9549f38bf26ULL, &gsdpk},
    {0xe1e91a6f1a2ca3c1ULL, &gsdhf},
    {0xe2d6c3bbaea37675ULL, &gsdac},
    {0xe316100bfaba585eULL, &gsd85},
    {0xe3a999126f16b2f7ULL, &gsde4},
    {0xe47820a12ed414bdULL, &gsd4k},
    {0xe498aad32de54f48ULL, &gsdmq},
    {0xe4d6670567fc9542ULL, &gsd7y},
    {0xe4d6875323ea02f2ULL, &gsd7u},
    {0xe5c9320f7e960ee5ULL, &gsd2f},
    {0xe734d89b723b1fb6ULL, &gsdic},
    {0xe75f5854d3e440a9ULL, &gsd3a},
    {0xe823e816077dbe13ULL, &gsd2w},
    {0xe82e3e5d30f31188ULL, &gsdcs},
    {0xe85b0f029d91a718ULL, &gsdhi},
    {0xe8753f6106bec909ULL, &gsdne},
    {0xe894147e1901df5fULL, &gsdc9},
    {0xe8b697c2523f1bfdULL, &gsddz},
    {0xe95520e7c0f97ff1ULL, &gsdlp},
    {0xe99c79c0090d60dfULL, &gsdao},
    {0xeb894e6d25a933b5ULL, &gsdns},
    {0xebc2353aeada7dc6ULL, &gsdoo},
    {0xec8ddc00e75902d6ULL, &gsdp5},
    {0xecb02997b2159c58ULL, &gsd99},
    {0xecc78b3e50550944ULL, &gsdlq},
    {0xedcd7752be6fb45bULL, &gsdm9},
    {0xedf023154a293b1cULL, &gsd5j},
    {0xee399fc175e190e2ULL, &gsd2x},
    {0xeeac7da6be5f1f61ULL, &gsd7s},
    {0xef2e3102f5e6f82dULL, &gsdje},
    {0xef99e14aedc47019ULL, &gsd14},
    {0xefadd66562585cd0ULL, &gsdf},
    {0xefc79dadccd6b025ULL, &gsdlw},
    {0xefef16e8143d4ccaULL, &gsd78},
    {0xf0d794709db54fceULL, &gsd8m},
    {0xf0e44171777c4293ULL, &gsd7i},
    {0xf133d94df4e95461ULL, &gsdha},
    {0xf1b1f44a376d213dULL, &gsdku},
    {0xf27431e7dcf032bcULL, &gsdm3},
    {0xf2f021c6d98a1718ULL, &gsdnv},
    {0xf31b702b7ebd027eULL, &gsd4e},
    {0xf350b412eef25d21ULL, &gsdl9},
    {0xf3b139f92d6961fbULL, &gsdkj},
    {0xf41ccad7c6daccf5ULL, &gsdme},
    {0xf45984845d6697ddULL, &gsd1n},
    {0xf4d2fc438cf905a5ULL, &gsdh},
    {0xf55715137e9cbf52ULL, &gsdek},
    {0xf5790daaeb3f0747ULL, &gsd7p},
    {0xf5dd2613e6c9cc95ULL, &gsdfc},
    {0xf6be6034e647662fULL, &gsdi3},
    {0xf73f4c9cd3832ca8ULL, &gsdbi},
    {0xf74725fecdc39c19ULL, &gsd1a},
    {0xf7fe560f597bb878ULL, &gsdr3},
    {0xf84aa3293805d7a1ULL, &gsdil},
    {0xf89bba82324b9097ULL, &gsdig},
    {0xf918a940ed34af16ULL, &gsdl0},
    {0xf9229a1d423eda11ULL, &gsdf9},
    {0xf9d34c4382d5340dULL, &gsdow},
    {0xfae00e0ecce5076aULL, &gsdq5},
    {0xfaee0bf65dbed307ULL, &gsd99},
    {0xfbc21e5f6cb65f0eULL, &gsdpq},
    {0xfc2085b3aa4961b1ULL, &gsdkm},
    {0xfc527ce7f96b8c6cULL, &gsd59},
    {0xfc6b08e1f2d15901ULL, &gsdkp},
    {0xfda1e2700f1b8449ULL, &gsd1x},
    {0xfdc06f4854472ef9ULL, &gsdiy},
    {0xfe571d4982bd0701ULL, &gsdih},
    {0xfe704eb6ae65b9d2ULL, &gsd9s},
    {0xfe74a8a757af0b88ULL, &gsd9q},
    {0xfe751d450d8c01e1ULL, &gsdi7},
    {0xfefaf12c04aeeb3cULL, &gsd28},
    {0xff9945f61bdaa646ULL, &gsd2b},
    {0xff9bc6d1b745351eULL, &gsdb2},
    {0xffe5e125f263fb0dULL, &gsdhx},
    {0xfffa6d7da3d3a905ULL, &gsdi9},
    {0xfffb7c971c243f78ULL, &gsdu},
};

#endif  // NS_GENERATED_GSD_SIGNATURE_DISPATCH_INC
