// 证书签名类型查询：只读读取 provisioning profile 的签名性质，供用量上报使用。
// 按需求删除证书弹窗与首页入口；不再自动弹出、不再占设置页。
#import "Core/SGCore.h"
#import "About.h"

static const NSTimeInterval kDay = 86400;
static const NSTimeInterval kFreeLongest = 8 * kDay;

static NSDictionary *profile(void) {
    static NSDictionary *read;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (!data.length) return;
        NSRange all = NSMakeRange(0, data.length);
        NSRange start = [data rangeOfData:[@"<?xml" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:all];
        NSRange end = [data rangeOfData:[@"</plist>" dataUsingEncoding:NSASCIIStringEncoding] options:NSDataSearchBackwards range:all];
        if (start.location == NSNotFound || end.location == NSNotFound || end.location < start.location) return;
        NSData *plist = [data subdataWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
        id parsed = [NSPropertyListSerialization propertyListWithData:plist options:0 format:NULL error:NULL];
        if ([parsed isKindOfClass:NSDictionary.class]) read = parsed;
    });
    return read;
}

static NSDate *dateIn(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:NSDate.class] ? value : nil;
}

NSString *SGCertificateKind(void) {
    NSDictionary *info = profile();
    if (!info) return @"none";
    if ([info[@"ProvisionsAllDevices"] boolValue]) return @"enterprise";
    NSDate *created = dateIn(info, @"CreationDate"), *expires = dateIn(info, @"ExpirationDate");
    if (!created || !expires) return nil;
    return [expires timeIntervalSinceDate:created] <= kFreeLongest ? @"free" : @"paid";
}
