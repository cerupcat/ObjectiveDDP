#import "MeteorClient.h"
#import "ObjectiveDDP.h"

using namespace Cedar::Matchers;
using namespace Cedar::Doubles;
using namespace Arguments;

SPEC_BEGIN(MeteorClientSpec)

describe(@"MeteorClient", ^{
    __block MeteorClient *meteorClient;
    __block ObjectiveDDP *ddp;

    beforeEach(^{
        ddp = nice_fake_for([ObjectiveDDP class]);
        meteorClient = [[[MeteorClient alloc] init] autorelease];
        ddp.delegate = meteorClient;
        meteorClient.ddp = ddp;
        meteorClient.authDelegate = nice_fake_for(@protocol(DDPAuthDelegate));
        spy_on(ddp);
    });

    it(@"is correctly initialized", ^{
        meteorClient.websocketReady should_not be_truthy;
        meteorClient.connected should_not be_truthy;
        meteorClient.usingAuth should_not be_truthy;
        meteorClient.loggedIn should_not be_truthy;
        meteorClient.collections should_not be_nil;
        meteorClient.subscriptions should_not be_nil;
    });
    
    describe(@"#logonWithUserName:password:", ^{
        context(@"when connected", ^{
            beforeEach(^{
                meteorClient.connected = YES;
                [meteorClient logonWithUsername:@"JesseJames"
                                       password:@"shot3mUp!"];
            });
            
            it(@"sends logon message correctly", ^{
                // XXX: add custom matcher that can query the params
                //      to see what user/pass was sent
                ddp should have_received(@selector(methodWithId:method:parameters:))
                .with(anything)
                .and_with(@"beginPasswordExchange")
                .and_with(anything);
            });
            
            describe(@"#logout", ^{
                beforeEach(^{
                    [meteorClient logout];
                });
                
                it(@"sends the logout message correclty", ^{
                    ddp should have_received(@selector(methodWithId:method:parameters:))
                    .with(anything)
                    .and_with(@"logout")
                    .and_with(anything);
                });
            });
        });
        
        context(@"when not connected", ^{
            beforeEach(^{
                meteorClient.connected = NO;
                [meteorClient logonWithUsername:@"JesseJames"
                                       password:@"shot3mUp!"];
            });
            
            it(@"does not send login message", ^{
                ddp should_not have_received(@selector(methodWithId:method:parameters:));
            });
        });
    });
    
    describe(@"#addSubscription:", ^{
        context(@"when connected", ^{
            beforeEach(^{
                meteorClient.connected = YES;
                [meteorClient addSubscription:@"a fancy subscription"];
            });

            it(@"should call ddp subscribe method", ^{
                ddp should have_received("subscribeWith:name:parameters:").with(anything)
                .and_with(@"a fancy subscription")
                .and_with(nil);
            });
        });

        context(@"when not connected", ^{
            beforeEach(^{
                meteorClient.connected = NO;
                [meteorClient addSubscription:@"a fancy subscription"];
            });

            it(@"should not call ddp subscribe method", ^{
                ddp should_not have_received("subscribeWith:name:parameters:");
            });
        });
    });

    describe(@"#removeSubscription:", ^{
        context(@"when not connected", ^{
            beforeEach(^{
                meteorClient.connected = YES;
                [meteorClient.subscriptions setObject:@"id1"
                                               forKey:@"fancySubscriptionName"];
                [meteorClient.subscriptions count] should equal(1);
                [meteorClient removeSubscription:@"fancySubscriptionName"];
            });

            it(@"removes subscription correctly", ^{
                ddp should have_received(@selector(unsubscribeWith:));
                [meteorClient.subscriptions count] should equal(0);
            });
        });

        context(@"when not connected", ^{
            beforeEach(^{
                meteorClient.connected = NO;
                [meteorClient.subscriptions setObject:@"id1"
                                               forKey:@"fancySubscriptionName"];
                [meteorClient.subscriptions count] should equal(1);
                [meteorClient removeSubscription:@"fancySubscriptionName"];
            });

            it(@"does not remove subscription", ^{
                ddp should_not have_received(@selector(unsubscribeWith:));
                [meteorClient.subscriptions count] should equal(1);
            });
        });
    });

    describe(@"#sendMethodWithName:parameters:notifyOnResponse", ^{
        __block NSString *methodId;

        context(@"when connected", ^{
            beforeEach(^{
                meteorClient.connected = YES;
                [meteorClient.methodIds count] should equal(0);
                methodId = [meteorClient sendWithMethodName:@"awesomeMethod"
                                                 parameters:@[]
                                           notifyOnResponse:YES];
            });

            it(@"stores a method id", ^{
                [meteorClient.methodIds count] should equal(1);
                [meteorClient.methodIds allObjects][0] should equal(methodId);
            });

            it(@"sends method command correctly", ^{
                ddp should have_received(@selector(methodWithId:method:parameters:))
                .with(methodId)
                .and_with(@"awesomeMethod")
                .and_with(@[]);
            });
        });

        context(@"when not connected", ^{
            beforeEach(^{
                meteorClient.connected = NO;
                [meteorClient.methodIds count] should equal(0);
                methodId = [meteorClient sendWithMethodName:@"awesomeMethod" parameters:@[] notifyOnResponse:YES];
            });

            it(@"does not store a method id", ^{
                [meteorClient.methodIds count] should equal(0);
            });

            it(@"does not send method command", ^{
                ddp should_not have_received(@selector(methodWithId:method:parameters:));
            });
        });
    });

    describe(@"#didOpen", ^{
        beforeEach(^{
            spy_on([NSNotificationCenter defaultCenter]);
            NSArray *array = [[[NSArray alloc] init] autorelease];
            meteorClient.collections = [NSMutableDictionary dictionaryWithDictionary:@{@"col1": array}];
            [meteorClient.collections count] should equal(1);
            [meteorClient didOpen];
        });

        it(@"sets the web socket state to ready", ^{
            meteorClient.websocketReady should be_truthy;
            [meteorClient.collections count] should equal(0);
            ddp should have_received(@selector(connectWithSession:version:support:));
        });

        it(@"sends a notification", ^{
            [NSNotificationCenter defaultCenter] should have_received(@selector(postNotificationName:object:))
            .with(MeteorClientDidConnectNotification)
            .and_with(meteorClient);
        });
    });

    describe(@"#didReceiveConnectionClose", ^{
        beforeEach(^{
            meteorClient.websocketReady = YES;
            meteorClient.connected = YES;
            [meteorClient didReceiveConnectionClose];
        });

        it(@"resets collections and reconnects web socket", ^{
            meteorClient.websocketReady should_not be_truthy;
            meteorClient.connected should_not be_truthy;
            ddp should have_received(@selector(connectWebSocket));
        });
    });
    
    describe(@"#didReceiveConnectionError", ^{
        beforeEach(^{
            spy_on([NSNotificationCenter defaultCenter]);
            meteorClient.websocketReady = YES;
            meteorClient.connected = YES;
            [meteorClient didReceiveConnectionError:nil];
        });
        
        it(@"resets collections and reconnects web socket", ^{
            meteorClient.websocketReady should_not be_truthy;
            meteorClient.connected should_not be_truthy;
            ddp should have_received(@selector(connectWebSocket));
        });

        it(@"sends a notification", ^{
            [NSNotificationCenter defaultCenter] should have_received(@selector(postNotificationName:object:))
            .with(MeteorClientDidDisconnectNotification)
            .and_with(meteorClient);
        });
    });

    describe(@"#didReceiveMessage", ^{
        beforeEach(^{
            spy_on([NSNotificationCenter defaultCenter]);
        });

        context(@"when called with method result message id", ^{
            __block NSString *key;
            __block NSDictionary *methodResponseMessage;

            beforeEach(^{
                key = @"key1";
                methodResponseMessage = @{
                    @"msg": @"result",
                    @"result": @"awesomesauce",
                    @"id": key
                };
                [meteorClient.methodIds addObject:key];
                [meteorClient didReceiveMessage:methodResponseMessage];
            });

            it(@"removes the message id", ^{
                [meteorClient.methodIds containsObject:key] should_not be_truthy;
            });

            it(@"sends a notification", ^{
                NSString *notificationName = [NSString stringWithFormat:@"response_%@", key];
                [NSNotificationCenter defaultCenter] should have_received(@selector(postNotificationName:object:userInfo:))
                    .with(notificationName)
                    .and_with(meteorClient)
                    .and_with(methodResponseMessage[@"result"]);
            });
        });
        
        context(@"when called with a login challenge response", ^{
            beforeEach(^{
                meteorClient.srpUser = (SRPUser *)malloc(sizeof(SRPUser));
                meteorClient.srpUser->Astr = [@"astringy" cStringUsingEncoding:NSASCIIStringEncoding];
                
                meteorClient.connected = YES;
                meteorClient.password = @"ardv4rkz";
                NSDictionary *challengeMessage = @{@"msg": @"result",
                                                   @"result": @{@"B": @"bee",
                                                                @"identity": @"ident",
                                                                @"salt": @"pepper"}};
                [meteorClient didReceiveMessage:challengeMessage];
            });
            
            it(@"processes the message correclty", ^{
                ddp should have_received(@selector(methodWithId:method:parameters:))
                    .with(anything)
                    .and_with(@"login")
                    .and_with(anything);
            });
        });
        
        context(@"when called with an HAMK verification response", ^{
            beforeEach(^{
                meteorClient.password = @"w0nky";
                meteorClient.srpUser = (SRPUser *)malloc(sizeof(SRPUser));
                meteorClient.srpUser->HAMK = [@"hamk4u" cStringUsingEncoding:NSASCIIStringEncoding];
                NSDictionary *verificationeMessage = @{@"msg": @"result",
                                                       @"result": @{@"id": @"id123",
                                                                    @"HAMK": @"hamk4u",
                                                                    @"token": @"smokin"}};
                [meteorClient didReceiveMessage:verificationeMessage];
            });
            
            it(@"processes the message correctly", ^{
                meteorClient.sessionToken should equal(@"smokin");
            });
        });

        context(@"when called with an authentication error message", ^{
            __block NSDictionary *authErrorMessage;
            
            beforeEach(^{
                authErrorMessage = @{
                                     @"msg": @"result",
                                     @"error": @{@"error": @403,
                                                 @"reason":
                                                 @"are you kidding me?"}};
            });
            
            context(@"before max rejects occurs and connected", ^{
                beforeEach(^{
                    meteorClient.retryAttempts = 0;
                    meteorClient.userName = @"mknightsham";
                    meteorClient.password = @"iS33de4dp33pz";
                });
                
                context(@"when connected", ^{
                    beforeEach(^{
                        meteorClient.connected = YES;
                        [meteorClient didReceiveMessage:authErrorMessage];
                    });
                    
                    it(@"processes the message correctly", ^{
                        meteorClient.authDelegate should_not have_received(@selector(authenticationFailed:));
                        ddp should have_received(@selector(methodWithId:method:parameters:))
                            .with(anything)
                            .and_with(@"beginPasswordExchange")
                            .and_with(anything);
                    });
                });
                
                context(@"when not connected", ^{
                    beforeEach(^{
                        meteorClient.connected = NO;
                        [meteorClient didReceiveMessage:authErrorMessage];
                    });
                    
                    it(@"processes the message correctly", ^{
                        meteorClient.retryAttempts should equal(0);
                        meteorClient.authDelegate should have_received(@selector(authenticationFailed:)).with(@"are you kidding me?");
                    });
                });
            });
            
            context(@"after max rejects occurs", ^{
                beforeEach(^{
                    meteorClient.retryAttempts = 5;
                    [meteorClient didReceiveMessage:authErrorMessage];
                });
                
                it(@"processes the message correctly", ^{
                    meteorClient.retryAttempts should equal(0);
                    meteorClient.authDelegate should have_received(@selector(authenticationFailed:)).with(@"are you kidding me?");
                });
            });
        });
        
        context(@"when subscription is ready", ^{
            beforeEach(^{
                [meteorClient.subscriptions setObject:@"subid" forKey:@"subscriptionName"];
                NSDictionary *readyMessage = @{@"msg": @"ready", @"subs": @[@"subid"]};
                [meteorClient didReceiveMessage:readyMessage];
            });
            
            it(@"processes the message correctly", ^{
                SEL postSel = @selector(postNotificationName:object:);
                [NSNotificationCenter defaultCenter] should have_received(postSel)
                    .with(@"subscriptionName_ready")
                    .and_with(meteorClient);
            });
        });

        context(@"when called with an 'added' message", ^{
            beforeEach(^{
                NSDictionary *addedMessage = @{
                    @"msg": @"added",
                    @"id": @"id1",
                    @"collection": @"phrases",
                    @"fields": @{@"text": @"this is ridiculous"}
                };

                [meteorClient didReceiveMessage:addedMessage];
            });

            it(@"processes the message correctly", ^{
                [meteorClient.collections[@"phrases"] count] should equal(1);
                NSDictionary *phrase = meteorClient.collections[@"phrases"][0];
                phrase[@"text"] should equal(@"this is ridiculous");
                SEL postSel = @selector(postNotificationName:object:userInfo:);
                [NSNotificationCenter defaultCenter] should have_received(postSel).with(@"added")
                                                                                  .and_with(meteorClient)
                                                                                  .and_with(phrase);
                [NSNotificationCenter defaultCenter] should have_received(postSel).with(@"phrases_added")
                                                                                  .and_with(meteorClient)
                                                                                  .and_with(phrase);
            });

            context(@"when called with a changed message", ^{
                beforeEach(^{
                    NSDictionary *changedMessage = @{
                        @"msg": @"changed",
                        @"id": @"id1",
                        @"collection": @"phrases",
                        @"fields": @{@"text": @"this is really ridiculous"}
                    };

                    [meteorClient didReceiveMessage:changedMessage];
                });

                it(@"processes the message correctly", ^{
                    [meteorClient.collections[@"phrases"] count] should equal(1);
                    NSDictionary *phrase = meteorClient.collections[@"phrases"][0];
                    phrase[@"text"] should equal(@"this is really ridiculous");
                    SEL postSel = @selector(postNotificationName:object:userInfo:);
                    [NSNotificationCenter defaultCenter] should have_received(postSel).with(@"changed")
                                                                                       .and_with(meteorClient)
                                                                                       .and_with(phrase);
                    [NSNotificationCenter defaultCenter] should have_received(postSel).with(@"phrases_changed")
                                                                                       .and_with(meteorClient)
                                                                                       .and_with(phrase);
                });
            });

            context(@"when called with a removed message", ^{
                beforeEach(^{
                    NSDictionary *removedMessage = @{
                        @"msg": @"removed",
                        @"id": @"id1",
                        @"collection": @"phrases",
                    };

                    [meteorClient didReceiveMessage:removedMessage];
                });

                it(@"processes the message correctly", ^{
                    [meteorClient.collections[@"phrases"] count] should equal(0);
                    SEL postSel = @selector(postNotificationName:object:);
                    [NSNotificationCenter defaultCenter] should have_received(postSel).with(@"removed")
                                                                                      .and_with(meteorClient);
                    [NSNotificationCenter defaultCenter] should have_received(postSel).with(@"phrases_removed")
                                                                                      .and_with(meteorClient);
                });
            });
        });
    });
});

SPEC_END
