//
//  AppDelegate+NetException.m
//  ExamProject
//
//  Created by ksw on 2017/10/13.
//  Copyright © 2017年 SunYong. All rights reserved.
//  AppDelegate 添加分类统一进行错误处理

#import "AppDelegate+NetException.h"
#import "SYNetMananger.h"

@implementation AppDelegate (NetException)

// 统一处理网络部分异常
- (void)configHandleNetException{
    
    [SYNetMananger sharedInstance].exceptionBlock = ^(NSError * _Nullable error, NSMutableDictionary* result) {
        
        if(![result isKindOfClass:[NSDictionary class]]){
            return ;
        }
        
        // 统一处理网络异常错误信息
        if(error && [result allKeys].count == 0){
            // 这个地方就可以在内部不需要去判断error，统一直接判断result相关信息
            // result错误信息配置
            [result setObject:error.localizedDescription forKey:@"msg"];
        }
        
        // (单点登录)登录异常处理
        if([[result objectForKey:@"statusCode"] integerValue] == 401){
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"LoginNotification" object:nil];
        }
    };
}

@end
