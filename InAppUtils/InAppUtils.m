#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import "RCTLog.h"
#import "RCTUtils.h"
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
    NSArray *_transactionIdsToFinish;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
        _transactionIdsToFinish = [[NSArray alloc] init];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSLog(@"failed");
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    callback(@[RCTJSErrorFromNSError(transaction.error)]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state failed.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    NSDictionary *purchase = @{
                                               @"transactionIdentifier": transaction.transactionIdentifier,
                                               @"productIdentifier": transaction.payment.productIdentifier
                                               };
                    callback(@[[NSNull null], purchase]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state purchased.");
                }
                break;
            }
            case SKPaymentTransactionStateRestored:
                NSLog(@"restored");
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"purchasing");
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"deferred");
                break;
            default:
                break;
        }
    }
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }
    
    if(product) {
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        callback(@[@"restore_failed"]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = RCTKeyForInstance(@"purchasedTransactions");
    RCTResponseSenderBlock callback = _callbacks[key];
    NSString *finishKey = RCTKeyForInstance(@"finishTransactions");
    RCTResponseSenderBlock finishTransactionsCallback = _callbacks[finishKey];
    
    NSMutableArray *productsArrayForJS = [NSMutableArray array];
    for(SKPaymentTransaction *transaction in queue.transactions){
        if(transaction.transactionState == SKPaymentTransactionStatePurchased) {
            //if transaction is in transactions to finish array, finish it.
            if([_transactionIdsToFinish containsObject:  transaction.transactionIdentifier]){
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }
            NSDictionary *purchase = @{
                                       @"transactionIdentifier": transaction.transactionIdentifier,
                                       @"productIdentifier": transaction.payment.productIdentifier
                                       };
            
            [productsArrayForJS addObject:purchase];
        }
    }
    
    if (callback) {
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    }
    
    if(finishTransactionsCallback){
        finishTransactionsCallback(@[[NSNull null], [NSNull null]]);
        [_callbacks removeObjectForKey:finishKey];
    }
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(getPurchasedTransactions:(RCTResponseSenderBlock)callback){
    NSString *pendingTransactions = @"purchasedTransactions";
    _callbacks[RCTKeyForInstance(pendingTransactions)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(finishTransactions:(NSArray *)transactionIdentifiers callback:(RCTResponseSenderBlock) callback)
{
    NSString *finishTransactions = @"finishTransactions";
    _callbacks[RCTKeyForInstance(finishTransactions)] =callback;
    _transactionIdsToFinish = transactionIdentifiers;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    if([SKPaymentQueue canMakePayments]){
        SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                              initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
        productsRequest.delegate = self;
        _callbacks[RCTKeyForInstance(productsRequest)] = callback;
        [productsRequest start];
    } else {
        callback(@[@"not_available"]);
    }
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
        callback(@[@"not_available"]);
    } else {
        callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"downloadable": item.downloadable ? @"true" : @"false" ,
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      };
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

@end