// Product state experiment: the account's product type decides on-demand play and skips. The value
// is logged, and can be forced from preferences while the shape of the enum is being established.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGProbeLog.h"

typedef NSInteger (*SGProductIMP)(id, SEL);

static SGProductIMP sgProductIMP;

static NSInteger sgProduct(__unused id self, __unused SEL _cmd) {
    NSInteger real = sgProductIMP ? sgProductIMP(self, _cmd) : 0;
    NSNumber *forced = [[NSUserDefaults standardUserDefaults] objectForKey:@"spotifyglass.testproduct"];
    if (!forced) {
        static NSInteger last = NSIntegerMin;
        if (real != last) {
            last = real;
            SGProbeC("product type is %ld", (long)real);
        }
        return real;
    }
    return forced.integerValue;
}

__attribute__((constructor)) static void sgProductInstall(void) {
    Class cls = objc_getClass("_TtC18Account_CommonImpl42ProductInformationControllerImplementation");
    Method m = cls ? class_getInstanceMethod(cls, @selector(currentProduct)) : NULL;
    if (!m) { SGProbeC("product probe: class or method missing"); return; }
    const char *types = method_getTypeEncoding(m);
    if (!types || types[0] != 'q') { SGProbeC("product probe: unexpected encoding on %s", sel_getName(@selector(currentProduct))); return; }
    sgProductIMP = (SGProductIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)sgProduct);
    SGProbeC("product probe installed");
}
