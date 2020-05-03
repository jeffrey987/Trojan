//
//  ProxyConfHelper.m
//  Trojan
//
//  Created by ParadiseDuo on 2020/5/3.
//  Copyright © 2020 ParadiseDuo. All rights reserved.
//

#import "ProxyConfHelper.h"

#define kShadowsocksHelper [[NSBundle mainBundle] pathForResource:@"ProxyConfHelper" ofType:nil]

@implementation ProxyConfHelper

GCDWebServer *webServer = nil;

+ (void)callHelper:(NSArray*) arguments {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath:kShadowsocksHelper];
    
    // this log is very important
    NSLog(@"run shadowsocks helper: %@", kShadowsocksHelper);
    [task setArguments:arguments];

    NSPipe *stdoutpipe;
    stdoutpipe = [NSPipe pipe];
    [task setStandardOutput:stdoutpipe];

    NSPipe *stderrpipe;
    stderrpipe = [NSPipe pipe];
    [task setStandardError:stderrpipe];

    NSFileHandle *file;
    file = [stdoutpipe fileHandleForReading];

    [task launch];

    NSData *data;
    data = [file readDataToEndOfFile];

    NSString *string;
    string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string.length > 0) {
        NSLog(@"%@", string);
    }

    file = [stderrpipe fileHandleForReading];
    data = [file readDataToEndOfFile];
    string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string.length > 0) {
        NSLog(@"%@", string);
    }
}

+ (void)addArguments4ManualSpecifyNetworkServices:(NSMutableArray*) args {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    if (![defaults boolForKey:@"AutoConfigureNetworkServices"]) {
        NSArray* serviceKeys = [defaults arrayForKey:@"Proxy4NetworkServices"];
        if (serviceKeys) {
            for (NSString* key in serviceKeys) {
                [args addObject:@"--network-service"];
                [args addObject:key];
            }
        }
    }
}

+ (void)enablePACProxy:(NSString*) PACFilePath {
    //start server here and then using the string next line
    //next two lines can open gcdwebserver and work around pac file
    NSString *PACURLString = [self startPACServer: PACFilePath];//hi 可以切换成定制pac文件路径来达成使用定制文件路径
    NSURL* url = [NSURL URLWithString: PACURLString];
    NSMutableArray* args = [@[@"--mode", @"auto", @"--pac-url", [url absoluteString]]mutableCopy];
    
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self callHelper:args];
}

+ (void)enableGlobalProxy {
    NSUInteger port = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalSocks5.ListenPort"];
    
    NSMutableArray* args = [@[@"--mode", @"global", @"--port", [NSString stringWithFormat:@"%lu", (unsigned long)port]]mutableCopy];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"LocalHTTPOn"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"LocalHTTP.FollowGlobal"]) {
        NSUInteger privoxyPort = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalHTTP.ListenPort"];

        [args addObject:@"--privoxy-port"];
        [args addObject:[NSString stringWithFormat:@"%lu", (unsigned long)privoxyPort]];
    }
    
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self callHelper:args];
    [self stopPACServer];
}

+ (void)enableWhiteListProxy {
    // 基于全局socks5代理下使用ACL文件来进行白名单代理 不需要使用pac文件
    NSUInteger port = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalSocks5.ListenPort"];
    
    NSMutableArray* args = [@[@"--mode", @"global", @"--port", [NSString stringWithFormat:@"%lu", (unsigned long)port]]mutableCopy];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"LocalHTTPOn"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"LocalHTTP.FollowGlobal"]) {
        NSUInteger privoxyPort = [[NSUserDefaults standardUserDefaults]integerForKey:@"LocalHTTP.ListenPort"];
        
        [args addObject:@"--privoxy-port"];
        [args addObject:[NSString stringWithFormat:@"%lu", (unsigned long)privoxyPort]];
    }
    
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self callHelper:args];
    [self stopPACServer];
}

+ (void)disableProxy:(NSString*) PACFilePath {
    NSMutableArray* args = [@[@"--mode", @"off"]mutableCopy];
    [self addArguments4ManualSpecifyNetworkServices:args];
    [self callHelper:args];
    [self stopPACServer];
}

+ (NSString*)startPACServer:(NSString*) PACFilePath {
    //接受参数为以后使用定制PAC文件
    NSData * originalPACData;
    NSString * routerPath = @"/proxy.pac";
    if ([PACFilePath isEqual: @"hi"]) {//用默认路径来代替
        PACFilePath = [NSString stringWithFormat:@"%@/%@", NSHomeDirectory(), @"/Documents/Trojan/gfwlist.js"];
        originalPACData = [NSData dataWithContentsOfFile: [NSString stringWithFormat:@"%@/%@", NSHomeDirectory(), @"/Documents/Trojan/gfwlist.js"]];
    }else{//用定制路径来代替
        originalPACData = [NSData dataWithContentsOfFile: [NSString stringWithFormat:@"%@/%@/%@", NSHomeDirectory(), @".Trojan", PACFilePath]];
        routerPath = [NSString stringWithFormat:@"/%@",PACFilePath];
    }
    [self stopPACServer];
    webServer = [[GCDWebServer alloc] init];
    [webServer addHandlerForMethod:@"GET" path: routerPath requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return [GCDWebServerDataResponse responseWithData: originalPACData contentType:@"application/Trojan-proxy-autoconfig"];
    }
     ];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString * address = [defaults stringForKey:@"PacServer.ListenAddress"];
    int port = (short)[defaults integerForKey:@"PacServer.ListenPort"];

    [webServer startWithOptions:@{@"BindToLocalhost":@YES, @"Port":@(port)} error:nil];

    return [NSString stringWithFormat:@"%@%@:%d%@",@"http://",address,port,routerPath];
}

+ (void)stopPACServer {
    if ([webServer isRunning]) {
        [webServer stop];
    }
}

@end