/****************************************************************************
 Copyright (c) 2014-2016 Chukong Technologies Inc.
 Copyright (c) 2017-2018 Xiamen Yaji Software Co., Ltd.

 http://www.cocos2d-x.org

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 ****************************************************************************/

#include "platform/CCPlatformConfig.h"

#if CC_TARGET_PLATFORM == CC_PLATFORM_IOS

#import <WebKit/WKWebView.h>
#import <WebKit/WKUIDelegate.h>
#import <WebKit/WKNavigationDelegate.h>
#import <WebKit/WKNavigationAction.h>
#import <WebKit/WKScriptMessageHandler.h>
#import <WebKit/WKWebViewConfiguration.h>
#import <WebKit/WKUserContentController.h>
#import <WebKit/WKScriptMessage.h>

#include "UIWebViewImpl-ios.h"
#include "renderer/CCRenderer.h"
#include "base/CCDirector.h"
#include "platform/CCGLView.h"
#include "platform/ios/CCEAGLView-ios.h"
#include "platform/CCFileUtils.h"
#include "ui/UIWebView.h"
#import <JavaScriptCore/JavaScriptCore.h>


@interface UIWebViewWrapper : NSObject
@property (nonatomic) std::function<bool(std::string url)> shouldStartLoading;
@property (nonatomic) std::function<void(std::string url)> didFinishLoading;
@property (nonatomic) std::function<void(std::string url)> didFailLoading;
@property (nonatomic) std::function<void(std::string url)> onJsCallback;

@property(nonatomic, readonly, getter=canGoBack) BOOL canGoBack;
@property(nonatomic, readonly, getter=canGoForward) BOOL canGoForward;

+ (instancetype)newWebViewWrapper;

- (void)setVisible:(bool)visible;

- (void)setBounces:(bool)bounces;

- (void)setOpacityWebView:(float)opacity;

- (float)getOpacityWebView;

- (void)setBackgroundTransparent;

- (void)setFrameWithX:(float)x y:(float)y width:(float)width height:(float)height;

- (void)setJavascriptInterfaceScheme:(const std::string &)scheme;

- (void)loadData:(const std::string &)data MIMEType:(const std::string &)MIMEType textEncodingName:(const std::string &)encodingName baseURL:(const std::string &)baseURL;

- (void)loadHTMLString:(const std::string &)string baseURL:(const std::string &)baseURL;

- (void)loadUrl:(const std::string &)urlString cleanCachedData:(BOOL) needCleanCachedData;

- (void)loadFile:(const std::string &)filePath;

- (void)stopLoading;

- (void)reload;

- (void)evaluateJS:(const std::string &)js;

- (void)goBack;

- (void)goForward;

- (void)setScalesPageToFit:(const bool)scalesPageToFit;
@end

// add delegate to action the js method from js
@interface WeakScriptMessageDelegate : NSObject<WKScriptMessageHandler>

@property (nonatomic, assign) id<WKScriptMessageHandler> scriptDelegate;

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate;

@end

@implementation WeakScriptMessageDelegate

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate
{
    self = [super init];
    if (self) {
        _scriptDelegate = scriptDelegate;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.scriptDelegate userContentController:userContentController didReceiveScriptMessage:message];
}

@end

@interface UIWebViewWrapper () <WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property(nonatomic, retain) WKWebView *wkWebView;
@property (nonatomic, retain) UIButton *closeBtn;
@property (nonatomic, retain) UIActivityIndicatorView *loadingView;
@property (nonatomic, copy) NSString *jsScheme;
@property (nonatomic, strong) JSContext *jsContext;

@end

@implementation UIWebViewWrapper {

}

+ (instancetype) newWebViewWrapper {
    return [[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.wkWebView = nil;
        self.shouldStartLoading = nullptr;
        self.didFinishLoading = nullptr;
        self.didFailLoading = nullptr;
        self.jsContext = nil;
        self.closeBtn = nil;
    }
    return self;
}

- (void)dealloc {
    self.wkWebView.UIDelegate = nil;
    self.wkWebView.navigationDelegate = nil;
    [self.wkWebView stopLoading];
    [[self.wkWebView configuration].userContentController removeScriptMessageHandlerForName:@"js2native"];
    [self.wkWebView removeFromSuperview];
    [self.wkWebView release];
    self.wkWebView = nil;
    self.jsScheme = nil;
    self.jsContext = nil;
    if (self.loadingView) {
        [self.loadingView removeFromSuperview];
    }
    self.loadingView = nil;
    if (self.closeBtn) {
        [self.closeBtn removeFromSuperview];
    }
    self.closeBtn = nil;
    [super dealloc];
}

- (void)setupWebView {
    if (!self.wkWebView) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.userContentController = [[WKUserContentController alloc] init];
        [config.userContentController addScriptMessageHandler:[[WeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"js2native"];
        self.wkWebView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1, 1) configuration:config];
        self.wkWebView.UIDelegate = self;
        self.wkWebView.navigationDelegate = self;

        [self setBackgroundTransparent];
        self.wkWebView.tag = 999;
    }
    if (!self.loadingView) {
        self.loadingView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    }
    if (!self.wkWebView.superview) {
        auto view = cocos2d::Director::getInstance()->getOpenGLView();
        auto eaglview = (CCEAGLView *) view->getEAGLView();
        [eaglview addSubview:self.wkWebView];
        [eaglview addSubview:self.loadingView];
    }
}

- (void)setVisible:(bool)visible {
    if (!self.wkWebView) {[self setupWebView];}
    self.wkWebView.hidden = !visible;
}

- (void)setBounces:(bool)bounces {
  self.wkWebView.scrollView.bounces = bounces;
}

- (void)setOpacityWebView:(float)opacity {
    if (!self.wkWebView) { [self setupWebView]; }
    self.wkWebView.alpha = opacity;
    [self.wkWebView setOpaque:YES];
}

-(float) getOpacityWebView{
    return self.wkWebView.alpha;
}

-(void) setBackgroundTransparent{
    if (!self.wkWebView) {[self setupWebView];}
    [self.wkWebView setOpaque:NO];
    [self.wkWebView setBackgroundColor:[UIColor clearColor]];
}

- (void)setFrameWithX:(float)x y:(float)y width:(float)width height:(float)height {
    if (!self.wkWebView) {[self setupWebView];}
    CGRect newFrame = CGRectMake(x, y, width, height);
    if (!CGRectEqualToRect(self.wkWebView.frame, newFrame)) {
        self.wkWebView.frame = CGRectMake(x, y, width, height);
    }
    // 设置并显示 loading
    self.loadingView.center = CGPointMake(x + width / 2, y + height / 2);
    [self.loadingView startAnimating];

    auto director = cocos2d::Director::getInstance();
    auto glView = director->getOpenGLView();
    auto frameSize = glView->getFrameSize();
    auto scaleFactor = [static_cast<CCEAGLView *>(glView->getEAGLView()) contentScaleFactor];
    if (width == frameSize.width / scaleFactor && height == frameSize.height / scaleFactor) {
        [self addCloseBtn:CGSizeMake(width, height) withScale: scaleFactor];
        [self setCloseBtnHidden:NO];
    } else {
        [self setCloseBtnHidden:YES];
    }
}

- (void)setJavascriptInterfaceScheme:(const std::string &)scheme {
    self.jsScheme = @(scheme.c_str());
}

- (void)loadData:(const std::string &)data MIMEType:(const std::string &)MIMEType textEncodingName:(const std::string &)encodingName baseURL:(const std::string &)baseURL {
    auto path = [[NSBundle mainBundle] resourcePath];
    path = [path stringByAppendingPathComponent:@(baseURL.c_str() )];
    auto url = [NSURL fileURLWithPath:path];

    [self.wkWebView loadData:[NSData dataWithBytes:data.c_str() length:data.length()]
                    MIMEType:@(MIMEType.c_str())
       characterEncodingName:@(encodingName.c_str())
                     baseURL:url];
}

- (void)loadHTMLString:(const std::string &)string baseURL:(const std::string &)baseURL {
    if (!self.wkWebView) {[self setupWebView];}
    auto path = [[NSBundle mainBundle] resourcePath];
    path = [path stringByAppendingPathComponent:@(baseURL.c_str() )];
    auto url = [NSURL fileURLWithPath:path];
    [self.wkWebView loadHTMLString:@(string.c_str()) baseURL:url];
}

- (void)loadUrl:(const std::string &)urlString cleanCachedData:(BOOL) needCleanCachedData {
    if (!self.wkWebView) {[self setupWebView];}
    NSURL *url = [NSURL URLWithString:@(urlString.c_str())];

    NSURLRequest *request = nil;
    if (needCleanCachedData)
        request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    else
        request = [NSURLRequest requestWithURL:url];

    [self.wkWebView loadRequest:request];
}

- (void)loadFile:(const std::string &)filePath {
    if (!self.wkWebView) {[self setupWebView];}
    NSURL *url = [NSURL fileURLWithPath:@(filePath.c_str())];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.wkWebView loadRequest:request];
}

- (void)stopLoading {
    [self.wkWebView stopLoading];
    if (self.loadingView) {
        [self.loadingView stopAnimating];
        [self.loadingView setHidden:TRUE];
    }
}

- (void)reload {
    [self.wkWebView reload];
}

- (BOOL)canGoForward {
    return self.wkWebView.canGoForward;
}

- (BOOL)canGoBack {
    return self.wkWebView.canGoBack;
}

- (void)goBack {
    [self.wkWebView goBack];
}

- (void)goForward {
    [self.wkWebView goForward];
}

- (void)addCloseBtn:(CGSize) frameSize withScale:(float) scale {
    if (!self.wkWebView) {[self setupWebView];}
    if (!self.closeBtn) {
        self.closeBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        auto posX = frameSize.width - 80 / scale;
        auto posY = 8 / scale;
        auto width = 72 / scale;
        auto height = 72 / scale;
        self.closeBtn.frame = CGRectMake(posX, posY, width, height);
        [self.closeBtn setBackgroundImage:[UIImage imageNamed:@"panels_close.png"] forState:UIControlStateNormal];
        [self.closeBtn addTarget:self action:@selector(closeBtnClick:) forControlEvents:UIControlEventTouchUpInside];
        [self.closeBtn setHidden:YES];
    }
    if (!self.closeBtn.superview) {
        auto view = cocos2d::Director::getInstance()->getOpenGLView();
        auto eaglview = (CCEAGLView *) view->getEAGLView();
        [eaglview addSubview:self.closeBtn];
    }
}

// add the new func to show close btn
- (void)setCloseBtnHidden:(BOOL)isHidden {
    if (self.closeBtn) {
        [self.closeBtn setHidden:isHidden];
    }
}

// the callback from button
- (void)closeBtnClick:(UIButton*)button{
    if (self.onJsCallback){
        NSString *resultStr = @"0";
        self.onJsCallback([resultStr UTF8String]);
    }
}

- (void)evaluateJS:(const std::string &)js {
    if (!self.wkWebView) {[self setupWebView];}
    [self.wkWebView evaluateJavaScript:@(js.c_str()) completionHandler:nil];
    // todo modify support js callback
    // [self.wkWebView stringByEvaluatingJavaScriptFromString:@(js.c_str())];
}

- (void)setScalesPageToFit:(const bool)scalesPageToFit {
// TODO: there is not corresponding API in WK.
// https://stackoverflow.com/questions/26295277/wkwebview-equivalent-for-uiwebviews-scalespagetofit/43048514 seems has a solution,
// but it doesn't support setting it dynamically. If we want to set this feature dynamically, then it will be too complex.
}



#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *url = [webView.URL absoluteString];
    if ([navigationAction.request.URL.scheme isEqualToString:self.jsScheme]) {
        if (self.onJsCallback) {
            self.onJsCallback([navigationAction.request.URL.absoluteString UTF8String]);
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (self.shouldStartLoading && url) {
        if (self.shouldStartLoading([url UTF8String]) )
            decisionHandler(WKNavigationActionPolicyAllow);
        else
            decisionHandler(WKNavigationActionPolicyCancel);

        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.didFinishLoading) {
        NSString *url = [webView.URL absoluteString];
        if (url) {
            self.didFinishLoading([url UTF8String]);
        }
    }
    if (self.loadingView) {
        [self.loadingView stopAnimating];
        [self.loadingView setHidden:TRUE];
    }

}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (self.didFailLoading) {
        NSString *errorInfo = error.userInfo[NSURLErrorFailingURLStringErrorKey];
        if (errorInfo) {
            self.didFailLoading([errorInfo UTF8String]);
        }
    }
    if (self.loadingView) {
        [self.loadingView stopAnimating];
        [self.loadingView setHidden:TRUE];
    }
}

#pragma WKUIDelegate

// Implement js alert function.
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)())completionHandler
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Ok"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler();
                                                      }]];

    auto rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootViewController presentViewController:alertController animated:YES completion:^{}];
}

// WKScriptMessageHandler 协议方法
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"js2native"]) {
        // JS objects are automatically mapped to ObjC objects
        id messageBody = message.body;
        if ([messageBody isKindOfClass:[NSDictionary class]]) {
            NSNumber* action = messageBody[@"action"];
            NSString* param = messageBody[@"param"];
            NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] init];
            [dictionary setObject:[action stringValue] forKey:@"action"];
            if (param) {
                [dictionary setObject:param forKey:@"param"];
            }
            NSString *jsonString = nil;
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary
                                                               options:NSJSONWritingPrettyPrinted
                                                                 error:&error];
            if (!jsonData){
                NSLog(@"json data is null, error = %@", error);
            } else {
                // use js call back send json string to lua, don't need to define a new function
                jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                //模拟异步回调
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (self.onJsCallback) {
                        self.onJsCallback([jsonString UTF8String]);
                    }
                });
            }
        }
    }

    
}


@end



namespace cocos2d {
namespace experimental {
    namespace ui{

WebViewImpl::WebViewImpl(WebView *webView)
        : _uiWebViewWrapper([UIWebViewWrapper newWebViewWrapper]),
        _webView(webView) {

    _uiWebViewWrapper.shouldStartLoading = [this](std::string url) {
        if (this->_webView != NULL && this->_webView->_impl != NULL && this->_webView->_onShouldStartLoading) {
            return this->_webView->_onShouldStartLoading(this->_webView, url);
        }
        return true;
    };
    _uiWebViewWrapper.didFinishLoading = [this](std::string url) {
        if (this->_webView != NULL && this->_webView->_impl != NULL && this->_webView->_onDidFinishLoading) {
            this->_webView->_onDidFinishLoading(this->_webView, url);
        }
    };
    _uiWebViewWrapper.didFailLoading = [this](std::string url) {
        if (this->_webView != NULL && this->_webView->_impl != NULL && this->_webView->_onDidFailLoading) {
            this->_webView->_onDidFailLoading(this->_webView, url);
        }
    };
    _uiWebViewWrapper.onJsCallback = [this](std::string url) {
        if (this->_webView != NULL && this->_webView->_impl != NULL && this->_webView->_onJSCallback) {
            this->_webView->_onJSCallback(this->_webView, url);
        }
    };
}

WebViewImpl::~WebViewImpl(){
    [_uiWebViewWrapper release];
    _uiWebViewWrapper = nullptr;
}

void WebViewImpl::setJavascriptInterfaceScheme(const std::string &scheme) {
    [_uiWebViewWrapper setJavascriptInterfaceScheme:scheme];
}

void WebViewImpl::loadData(const Data &data,
                           const std::string &MIMEType,
                           const std::string &encoding,
                           const std::string &baseURL) {

    std::string dataString(reinterpret_cast<char *>(data.getBytes()), static_cast<unsigned int>(data.getSize()));
    [_uiWebViewWrapper loadData:dataString MIMEType:MIMEType textEncodingName:encoding baseURL:baseURL];
}

void WebViewImpl::loadHTMLString(const std::string &string, const std::string &baseURL) {
    [_uiWebViewWrapper loadHTMLString:string baseURL:baseURL];
}

void WebViewImpl::loadURL(const std::string &url) {
    this->loadURL(url, false);
}

void WebViewImpl::loadURL(const std::string &url, bool cleanCachedData) {
    [_uiWebViewWrapper loadUrl:url cleanCachedData:cleanCachedData];
}

void WebViewImpl::loadFile(const std::string &fileName) {
    auto fullPath = cocos2d::FileUtils::getInstance()->fullPathForFilename(fileName);
    [_uiWebViewWrapper loadFile:fullPath];
}

void WebViewImpl::stopLoading() {
    [_uiWebViewWrapper stopLoading];
}

void WebViewImpl::reload() {
    [_uiWebViewWrapper reload];
}

bool WebViewImpl::canGoBack() {
    return _uiWebViewWrapper.canGoBack;
}

bool WebViewImpl::canGoForward() {
    return _uiWebViewWrapper.canGoForward;
}

void WebViewImpl::goBack() {
    [_uiWebViewWrapper goBack];
}

void WebViewImpl::goForward() {
    [_uiWebViewWrapper goForward];
}

void WebViewImpl::evaluateJS(const std::string &js) {
    [_uiWebViewWrapper evaluateJS:js];
}

void WebViewImpl::setBounces(bool bounces) {
    [_uiWebViewWrapper setBounces:bounces];
}

void WebViewImpl::setScalesPageToFit(const bool scalesPageToFit) {
    [_uiWebViewWrapper setScalesPageToFit:scalesPageToFit];
}

void WebViewImpl::draw(cocos2d::Renderer *renderer, cocos2d::Mat4 const &transform, uint32_t flags) {
    if (flags & cocos2d::Node::FLAGS_TRANSFORM_DIRTY) {

        auto director = cocos2d::Director::getInstance();
        auto glView = director->getOpenGLView();
        auto frameSize = glView->getFrameSize();

        auto scaleFactor = [static_cast<CCEAGLView *>(glView->getEAGLView()) contentScaleFactor];

        auto winSize = director->getWinSize();

        auto leftBottom = this->_webView->convertToWorldSpace(cocos2d::Vec2::ZERO);
        auto rightTop = this->_webView->convertToWorldSpace(cocos2d::Vec2(this->_webView->getContentSize().width, this->_webView->getContentSize().height));

        auto x = (frameSize.width / 2 + (leftBottom.x - winSize.width / 2) * glView->getScaleX()) / scaleFactor;
        auto y = (frameSize.height / 2 - (rightTop.y - winSize.height / 2) * glView->getScaleY()) / scaleFactor;
        auto width = (rightTop.x - leftBottom.x) * glView->getScaleX() / scaleFactor;
        auto height = (rightTop.y - leftBottom.y) * glView->getScaleY() / scaleFactor;

        [_uiWebViewWrapper setFrameWithX:x
                                      y:y
                                  width:width
                                 height:height];
    }
}

void WebViewImpl::setVisible(bool visible){
    [_uiWebViewWrapper setVisible:visible];
}

void WebViewImpl::setOpacityWebView(float opacity){
    [_uiWebViewWrapper setOpacityWebView: opacity];
}

float WebViewImpl::getOpacityWebView() const{
    return [_uiWebViewWrapper getOpacityWebView];
}

void WebViewImpl::setBackgroundTransparent(){
    [_uiWebViewWrapper setBackgroundTransparent];
}


    } // namespace ui
} // namespace experimental
} //namespace cocos2d

#endif // CC_TARGET_PLATFORM == CC_PLATFORM_IOS
