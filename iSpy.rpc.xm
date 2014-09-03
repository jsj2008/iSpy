#include <stack>
#include <fcntl.h>
#include <stdio.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <stdbool.h>
#include <pthread.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <objc/objc.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <netinet/in.h>
#import  <Security/Security.h>
#import  <Security/SecCertificate.h>
#include <CFNetwork/CFNetwork.h>
#include <CFNetwork/CFProxySupport.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFStream.h>
#import  <Foundation/NSJSONSerialization.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>
#include "iSpy.common.h"
#include "iSpy.instance.h"
#include "iSpy.class.h"
#include "hooks_C_system_calls.h"
#include "hooks_CoreFoundation.h"
#include <dlfcn.h>
#include <mach-o/nlist.h>
#include <semaphore.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import "typestring.h"
#import "iSpy.rpc.h"

/*
 *
 * RPC handlers take exactly one argument: an NSDictionary of parameter/value pairs.
 *
 * RPC handlers return an NSDictionary that will be sent to the RPC caller as JSON,
 * either via a websocket (if initiated by websocket) or as a response to an HTTP POST.
 *
 * You can also return nil, that's fine too. For websockets nothing will happen; for POST
 * requests it'll cause a blank response to be sent back to the RPC caller.
 *
 */
@implementation RPCHandler

-(NSDictionary *) setMsgSendLoggingState:(NSDictionary *) args {
	NSString *state = [args objectForKey:@"state"];

	if( ! state || ( ! [state isEqualToString:@"true"] && ! [state isEqualToString:@"false"] )) {
		ispy_log_debug(LOG_HTTP, "setMsgSendLoggingState: Invalid state");
		return @{
			@"status":@"error",
			@"errorMessage":@"Invalid status"
		};
	}

	if([state isEqualToString:@"true"]) {
		[[iSpy sharedInstance] msgSend_enableLogging];
	}
	else if([state isEqualToString:@"false"]) {
		[[iSpy sharedInstance] msgSend_disableLogging];
	}

	return @{ @"status":state };
}


-(NSDictionary *) testJSONRPC:(NSDictionary *)args {
	return @{ @"REPLY_TEST":args };
}

-(NSDictionary *) ASLR:(NSDictionary *)args {
	return @{ @"ASLR": [NSString stringWithFormat:@"%d", [[iSpy sharedInstance] ASLR]] };
}

/*
args = NSDictionary containing an object ("classes"), which is is an NSArray of NSDictionaries, like so:
{
	"classes": [
		{
			"class": "ClassName1",
			"methods": [ @"Method1", @"Method2", ... ]
		},
		{
			"class": "ClassName2",
			"methods": [ @"MethodX", @"MethodY", ... ]
		},
		...
	]
}

If "methods" is nil, assume all methods in class.
*/
-(NSDictionary *) addMethodsToWhitelist:(NSDictionary *)args {
    int i, numClasses, m, numMethods;
    static std::tr1::unordered_map<std::string, std::tr1::unordered_map<std::string, int> > WhitelistClassMap;

    NSArray *classes = [args objectForKey:@"classes"];
    if(classes == nil) {
    	return @{ 
    		@"status": @"error",
    		@"errorMessage": @"Empty class list"
    	};
    }

	numClasses = [classes count];

    // Iterate through all the class names, adding each one to our lookup table
    for(i = 0; i < numClasses; i++) {
    	NSDictionary *itemToAdd = [classes objectAtIndex:i];
    	NSString *name = [itemToAdd objectForKey:@"class"];
    	if(!name) {
    		continue;
    	}

    	NSArray *methods = [itemToAdd objectForKey:@"methods"];
    	if(!methods) {
    		continue;
    	}

    	numMethods = [methods count];
    	if(!numMethods) {
    		continue;
    	}

    	for(m = 0; m < numMethods; m++) {
    		NSString *methodName = [methods objectAtIndex:m];
    		if(!methodName) {
    			continue;
    		}
    		std::string *classNameString = new std::string([name UTF8String]);
    		std::string *methodNameString = new std::string([methodName UTF8String]);
    		if(!classNameString || !methodNameString) {
    			if(methodNameString)
    				delete methodNameString;
    			if(classNameString)
    				delete classNameString;
    			continue;
    		}
    		ispy_log_debug(LOG_GENERAL, "[Whitelist] Adding [%s %s]", classNameString->c_str(), methodNameString->c_str());
            whitelist_add_method(classNameString, methodNameString);
    		delete methodNameString;
    		delete classNameString;
    	}
    }
    return @{ @"status": @"OK" };
}

-(NSDictionary *) classList:(NSDictionary *)args {
	NSArray *classes = [[iSpy sharedInstance] classes];
	return @{ 
		@"status": @"OK",
		@"classes": classes 
	};
}

-(NSDictionary *) classListWithProtocolInfo:(NSDictionary *)args {
	NSArray *classes = [[iSpy sharedInstance] classesWithSuperClassAndProtocolInfo];
	return @{ 
		@"status": @"OK",
		@"classes": classes 
	};
}

@end


