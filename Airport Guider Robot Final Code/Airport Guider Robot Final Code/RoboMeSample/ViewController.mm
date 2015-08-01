//
//  ViewController.m
//
//
//  Copyright (c) 2013 WowWee Group Limited. All rights reserved.
//

#import "ViewController.h"
#import "GCDAsyncSocket.h"
#include <ifaddrs.h>
#include <arpa/inet.h>
#import <AddressBookUI/AddressBookUI.h>
#import "AFHTTPRequestOperationManager.h"
#import "KairosSDK.h"
#import "AppDelegate.h"



#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <CoreAudioKit/CoreAudioKit.h>
#import <AudioUnit/AudioUnit.h>
#import <EventKit/EventKit.h>

#import "opencv2/opencv.hpp"
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/objdetect/objdetect.hpp>
#include <opencv2/core/core.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/imgproc/imgproc.hpp>

#import <CoreMedia/CoreMedia.h>

#define BASE_URL "http://cs590bdnlpservices.mybluemix.net/api/service"
#define BASE_URL1 "http://api.openweathermap.org/data/2.5/weather?"
#define BASE_URL2 "http://tts-api.com/tts.mp3?"


#define WELCOME_MSG  0
#define ECHO_MSG     1
#define WARNING_MSG  2

#define READ_TIMEOUT 15.0
#define READ_TIMEOUT_EXTENSION 10.0

#define FORMAT(format, ...) [NSString stringWithFormat:(format), ##__VA_ARGS__]
#define PORT 1234


@interface ViewController () {
    dispatch_queue_t socketQueue;
    NSMutableArray *connectedSockets;
    BOOL isRunning;
    
    GCDAsyncSocket *listenSocket;
   
    
}

@property (nonatomic, strong) RoboMe *roboMe;
@property (nonatomic, strong) CMAccelerometerData *previousAccelerometerData;
@property (nonatomic, strong) NSArray *tags;
@property (nonatomic, strong) NSArray *tokens;
@property (nonatomic, strong) AppDelegate *appDelegate;
@property (nonatomic, strong) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UITextField *nameField;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (strong, nonatomic) IBOutlet UIView *webSuperView;
@property (strong, nonatomic) IBOutlet UIWebView *webView;
@end
const unsigned char SpeechKitApplicationKey[] = {0xc0,0x56,0xc5,0x76,0xa2,0x37,0x66,0xdf,0xd6,0xf7,0x11,0x97,0xb9,0xbd,0xb8,0x89,0xdd,0x71,0xab,0x43,0xe5,0x72,0xb6,0xd4,0x82,0x5c,0xbe,0xd0,0x4e,0x37,0x12,0x0e,0x8d,0xd7,0x84,0x2f,0x0e,0xeb,0x0e,0xe4,0xe2,0x20,0x7c,0x9c,0xdd,0x34,0x25,0xba,0xa5,0xd0,0xfd,0x8b,0x42,0xb3,0x5f,0xc5,0x10,0x1d,0x95,0x5e,0x54,0xa7,0x6c,0xe1};
using namespace std;
using namespace cv;

@implementation ViewController

-(void)buttonAddReminder:(id)sender{
}
- (IBAction)dismisskeyboard:(id)sender {
    [self.nameField resignFirstResponder];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [KairosSDK initWithAppId:@"4fcbcb96" appKey:@"d478253f19206f1ef53bc4338b0fc823"];
    [KairosSDK setPreferredCameraType:KairosCameraFront];
    [KairosSDK setEnableFlash:YES];
    [KairosSDK setEnableShutterSound:NO];
    [KairosSDK setStillImageTintColor:@"DBDB4D"];
    [KairosSDK setProgressBarTintColor:@"FFFF00"];
    [KairosSDK setErrorMessageMoveCloser:@"Yo move closer, dude!"];
    // create RoboMe object
    self.roboMe = [[RoboMe alloc] initWithDelegate: self];
    
    self.appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate ];
    [self.appDelegate setupSpeechKitConnection];
    // start listening for events from RoboMe
    [self.roboMe startListening];
    
    // Do any additional setup after loading the view, typically from a nib.
    socketQueue = dispatch_queue_create("socketQueue", NULL);
    
    listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:socketQueue];
    
    // Setup an array to store all accepted client connections
    connectedSockets = [[NSMutableArray alloc] initWithCapacity:1];
    
    isRunning = NO;
    
    NSLog(@"%@", [self getIPAddress]);
    
    [self toggleSocketState];   //Statrting the Socket
    
    self.eventStore = [[EKEventStore alloc]init];
   self.eventStoreAccessGranted = NO;
   [self.eventStore requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL success, NSError *error)
   {
     self.eventStoreAccessGranted = success;
     if(!success)
      NSLog(@"");
    }];
    
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    //[self startUpdatesWithSliderValue:0.05];
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self setupCamera];
    [self turnCameraOn];
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
   // [self stopUpdates];
    [self turnCameraOff];
}

- (void)setupCamera
{
    _captureDevice = nil;
    
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    for (AVCaptureDevice *device in devices)
    {
        if (device.position == AVCaptureDevicePositionFront && !_useBackCamera)
        {
            _captureDevice = device;
            break;
        }
        if (device.position == AVCaptureDevicePositionBack && _useBackCamera)
        {
            _captureDevice = device;
            break;
        }
    }
    
    if (!_captureDevice)
        _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}


- (void)turnCameraOn
{
    NSError *error;
    
    _session = [[AVCaptureSession alloc] init];
    [_session beginConfiguration];
    [_session setSessionPreset:AVCaptureSessionPresetMedium];
    
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice error:&error];
    
    if (input == nil)
        NSLog(@"%@", error);
    
    [_session addInput:input];
    
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    [output setSampleBufferDelegate:self queue:dispatch_queue_create("myQueue", NULL)];
    output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
    output.alwaysDiscardsLateVideoFrames = YES;
    
    [_session addOutput:output];
    
    [_session commitConfiguration];
    [_session startRunning];
}

- (void)turnCameraOff
{
    [_session stopRunning];
    _session = nil;
}



static void ReleaseDataCallback(void *info, const void *data, size_t size)
{
#pragma unused(data)
#pragma unused(size)
    IplImage *iplImage = (IplImage *)info;
    cvReleaseImage(&iplImage);
}

- (CGImageRef)getCGImageFromIplImage:(IplImage*)iplImage
{
    size_t bitsPerComponent = 8;
    size_t bytesPerRow = iplImage->widthStep;
    
    size_t bitsPerPixel;
    CGColorSpaceRef space;
    
    if (iplImage->nChannels == 1)
    {
        bitsPerPixel = 8;
        space = CGColorSpaceCreateDeviceGray();
    }
    else if (iplImage->nChannels == 3)
    {
        bitsPerPixel = 24;
        space = CGColorSpaceCreateDeviceRGB();
    }
    else if (iplImage->nChannels == 4)
    {
        bitsPerPixel = 32;
        space = CGColorSpaceCreateDeviceRGB();
    }
    else
    {
        abort();
    }
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;
    CGDataProviderRef provider = CGDataProviderCreateWithData(iplImage,
                                                              iplImage->imageData,
                                                              0,
                                                              ReleaseDataCallback);
    const CGFloat *decode = NULL;
    bool shouldInterpolate = true;
    CGColorRenderingIntent intent = kCGRenderingIntentDefault;
    
    CGImageRef cgImageRef = CGImageCreate(iplImage->width,
                                          iplImage->height,
                                          bitsPerComponent,
                                          bitsPerPixel,
                                          bytesPerRow,
                                          space,
                                          bitmapInfo,
                                          provider,
                                          decode,
                                          shouldInterpolate,
                                          intent);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return cgImageRef;
}

#pragma mark - getting UIImage from Ipl Image

- (UIImage*)getUIImageFromIplImage:(IplImage*)iplImage
{
    CGImageRef cgImage = [self getCGImageFromIplImage:iplImage];
    UIImage *uiImage = [[UIImage alloc] initWithCGImage:cgImage
                                                  scale:1.0
                                            orientation:UIImageOrientationUp];
    
    CGImageRelease(cgImage);
    return uiImage;
}




#pragma mark - AVCaptureFoundation Delegate Methods

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    int width = (int)CVPixelBufferGetWidth(imageBuffer);
    int height = (int)CVPixelBufferGetHeight(imageBuffer);
    
    IplImage *iplimage;
    if (baseAddress)
    {
        iplimage = cvCreateImageHeader(cvSize(width, height), IPL_DEPTH_8U, 4);
        iplimage->imageData = (char*)baseAddress;
    }
    
    IplImage *workingCopy = cvCreateImage(cvSize(height, width), IPL_DEPTH_8U, 4);
    
    if (_captureDevice.position == AVCaptureDevicePositionFront)
    {
        cvTranspose(iplimage, workingCopy);
    }
    else
    {
        cvTranspose(iplimage, workingCopy);
        cvFlip(workingCopy, nil, 1);
    }
    
    cvReleaseImageHeader(&iplimage);
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    [self didCaptureIplImage:workingCopy];
}



// Print out given text to text view
- (void)displayText: (NSString *)text {
    NSString *outputTxt = [NSString stringWithFormat: @"%@\n%@", self.outputTextView.text, text];
    
    // print command to output box
    [self.outputTextView setText: outputTxt];
    
    // scroll to bottom
    [self.outputTextView scrollRangeToVisible:NSMakeRange([self.outputTextView.text length], 0)];
}

- (IBAction)recordButtonTapped:(id)sender {
    self.recordButton.selected = !self.recordButton.isSelected;
    
    // This will initialize a new speech recognizer instance
    if (self.recordButton.isSelected) {
        self.voiceSearch = [[SKRecognizer alloc] initWithType:SKSearchRecognizerType
                                                    detection:SKShortEndOfSpeechDetection
                                                     language:@"en_US"
                                                     delegate:self];
    }
    
    // This will stop existing speech recognizer processes
    else {
        if (self.voiceSearch) {
            [self.voiceSearch stopRecording];
            [self.voiceSearch cancel];
        }
    }
}

#pragma mark - RoboMeConnectionDelegate

// Event commands received from RoboMe
- (void)commandReceived:(IncomingRobotCommand)command {
    // Display incoming robot command in text view
    [self displayText: [NSString stringWithFormat: @"Received: %@" ,[RoboMeCommandHelper incomingRobotCommandToString: command]]];
    
    // To check the type of command from RoboMe is a sensor status use the RoboMeCommandHelper class
    if([RoboMeCommandHelper isSensorStatus: command]){
        // Read the sensor status
        SensorStatus *sensors = [RoboMeCommandHelper readSensorStatus: command];
        
        // Update labels
        [self.edgeLabel setText: (sensors.edge ? @"ON" : @"OFF")];
        [self.chest20cmLabel setText: (sensors.chest_20cm ? @"ON" : @"OFF")];
        [self.chest50cmLabel setText: (sensors.chest_50cm ? @"ON" : @"OFF")];
        [self.cheat100cmLabel setText: (sensors.chest_100cm ? @"ON" : @"OFF")];
    }
}

- (void)volumeChanged:(float)volume {
    if([self.roboMe isRoboMeConnected] && volume < 0.75) {
        [self displayText: @"Volume needs to be set above 75% to send commands"];
    }
}

- (void)roboMeConnected {
    [self displayText: @"RoboMe Connected!"];
}

- (void)roboMeDisconnected {
    [self displayText: @"RoboMe Disconnected"];
}





- (void)recognizer:(SKRecognizer *)recognizer didFinishWithResults:(SKRecognition *)results {
    long numOfResults = [results.results count];
    
    if (numOfResults > 0) {
        // update the text of text field with best result from SpeechKit
        //self.searchTextField.text = [results firstResult];
        [self performCommand:[results firstResult]];
    }
    
    self.recordButton.selected = !self.recordButton.isSelected;
    
    if (self.voiceSearch) {
        [self.voiceSearch cancel];
    }
}


- (void)recognizer:(SKRecognizer *)recognizer didFinishWithError:(NSError *)error suggestion:(NSString *)suggestion {
    self.recordButton.selected = NO;
    
    
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                    message:[error localizedDescription]
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
}

#pragma mark -
#pragma mark User-Defined Robo Movement

- (NSString *)direction:(NSString *)message {
    
    return @"";
}

- (void)perform:(NSString *)command {
    
    [self performCommand:command];

    
}

-(void)performCommand:(NSString *)command{
    NSString *cmd = [command uppercaseString];
   // UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Info" message:command delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
    if ([cmd isEqualToString:@"RIGHT"]) {
        [self.roboMe sendCommand: kRobot_TurnRightSpeed5];
       [self.roboMe sendCommand: kRobot_MoveForwardFastest];
        [self speakright:command];
        //[alert show];
    } else if ([cmd isEqualToString:@"LEFT"]) {
        [self.roboMe sendCommand: kRobot_TurnLeftSpeed5];
        [self.roboMe sendCommand:kRobot_MoveForwardFastest];
       [self speakleft:command];
        //[alert show];
    } else if ([cmd isEqualToString:@"BACKWARD"]) {
        [self.roboMe sendCommand:kRobot_Stop];
        [self.roboMe sendCommand: kRobot_MoveBackwardFastest];
        [self speakback:command];
        //[alert show];
    } else if ([cmd isEqualToString:@"FORWARD"]) {
        [self.roboMe sendCommand: kRobot_MoveForwardFastest];
        [self speakforward:command];
        //[alert show];
    } else if([cmd isEqualToString:@"STOP"]){
        [self.roboMe sendCommand:kRobot_Stop];
    } else if([cmd isEqualToString:@"MAKE CALL"]){
        [self makecall:command];
    }  else if ([cmd isEqualToString:@"PLAY MUSIC"]){
        [self playMusic:command];
    }   else if ([cmd isEqualToString:@"WHO ARE YOU"]){
        [self texttospeechconv:command];
    }   else if([cmd isEqualToString:@"HI BUDDY"]){
        [self texttospeechconv1:command];
    }   else if([cmd isEqualToString:@"HOW ARE YOU"]){
        [self texttospeechconv2:command];
    }   else if([cmd isEqualToString:@"WHAT ARE YOU DOING"]){
        [self texttospeechconv3:command];
    }   else if ([cmd isEqualToString:@"WHAT IS YOUR HOBBY"]){
        [self texttospeechconv4:command];
    }   else if ([cmd isEqualToString:@"WHAT DO YOU LIKE TO DO"]){
        [self texttospeechconv5:command];
    }   else if ([cmd isEqualToString:@"DO YOU LIKE DONALD TRUMP"]){
        [self texttospeechconv6:command];
    }
        else if ([cmd isEqualToString:@"KLM 535"]){
            
            NSLog(@"FLIGHT NUMBER %@",cmd);
            NSString *newStr = [cmd stringByReplacingOccurrencesOfString:@" " withString:@""];
            NSLog(@"TRIMMED FLIGHT NUMBER %@", newStr);
           
            [self openURLinWebView:[NSString stringWithFormat:@"https://www.google.co.in/#q=%@",newStr]];//[self speakback:@"KLM 535 Information"];
        }else if([cmd isEqualToString:@"THANK YOU"]){
            [self dismissWebView];
        }
    
}

-(void)openURLinWebView:(NSString *)url{
    //self.webView.frame = CGRectMake(0, -999, self.webView.frame.size.width, self.webView.frame.size.height);
    [self.view addSubview:self.webSuperView];
    
        //self.webView.frame = CGRectMake(0, 0, self.webView.frame.size.width, self.webView.frame.size.height);
    
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
    
}

-(void)dismissWebView{
    //self.webView.frame = CGRectMake(0, 0, self.webView.frame.size.width, self.webView.frame.size.height);
    
    //[UIView animateWithDuration:0.5 animations:^{
        //self.webView.frame = CGRectMake(0, -999, self.webView.frame.size.width, self.webView.frame.size.height);
        [self.webSuperView removeFromSuperview];
    //}];
}

-(void)performNLP:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    NSString *sentense = [command stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *url = [NSString stringWithFormat:@"%s/tokenize/%@", BASE_URL, sentense];
   // NSString *comnd = [command string];
    NSLog(@"%@", url);
    
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"JSON: %@", responseObject);
        
        _tokens = [responseObject objectForKey:@"results"];
        //_tags = [responseObject objectForKey:@"tags"];
        
         NSLog(@"Tags are: %@", _tags);
        
    
        
    }  failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
        
       
    }];
    
}
- (IBAction)Recognize:(id)sender {
    [KairosSDK imageCaptureRecognizeWithThreshold:@".75"
                                      galleryName:@"gallery1"
                                          success:^(NSDictionary *response, UIImage *image) {
                                              NSString *subjectName = [[[[response objectForKey:@"images"] objectAtIndex:0] objectForKey:@"transaction"] objectForKey:@"subject"];
                                              NSString *text = [NSString stringWithFormat:@"Hello %@",subjectName];
                                              [self texttospeechconv7:text];
                                              NSLog(@"%@", response);
                                              
                                          } failure:^(NSDictionary *response, UIImage *image) {
                                              
                                              NSLog(@"%@", response);
                                              
                                          }];
}

- (IBAction)Register:(id)sender {
    [KairosSDK imageCaptureEnrollWithSubjectId:self.nameField.text
                                   galleryName:@"gallery1"
                                       success:^(NSDictionary *response, UIImage *image) {
                                           
                                           NSLog(@"%@", response);
                                           
                                       } failure:^(NSDictionary *response, UIImage *image) {
                                           
                                           NSLog(@"%@", response);
                                           
                                       }];

}


-(void)texttospeechconv:(NSString *)command{

    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"I AM AN AIRPORT GUIDE ROBOT"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
        
        _audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [_audioPlayer prepareToPlay];
        [_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}

-(void)texttospeechconv7:(NSString *)command{
    
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    //NSString *messageBody = [NSString stringWithFormat:@"I AM AN AIRPORT GUIDE ROBOT"];
    
    //////////
    
    NSString *sentence = [command stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:NO error:nil];
        
        _audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [_audioPlayer prepareToPlay];
        [_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}


-(void)speakleft:(NSString *)command{

    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"Taking Left direction"];
        
        //////////
        
        NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        
        
        NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
        
        NSLog(@"url is: %@",url);
        
        manager.responseSerializer = [AFHTTPResponseSerializer serializer];
        [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
            
            
            
            NSLog(@"NSObject: %@", responseObject);
            
            NSData *audioData = responseObject;
            
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            
            self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
            
            [self->_audioPlayer prepareToPlay];
            [self->_audioPlayer play];
            
            // NSLog(@"responseString: %@", responseString);
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                            message:[error description]
                                                           delegate:nil
                                                  cancelButtonTitle:@"Ok"
                                                  otherButtonTitles:nil, nil];
            [alert show];
        }];
    

}

-(void)speakright:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"Taking right direction"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}


-(void)speakforward:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"Moving Forward"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}


-(void)speakback:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"Moving backward"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}



-(void)texttospeechconv1:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"Hello BRO"];
    
    
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}

-(void)texttospeechconv2:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"I AM GOOD THANK YOU HOW ARE YOU"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}

-(void)texttospeechconv3:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"I AM HELPING YOU IN GIVING DEMO"];
    
    
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}

-(void)texttospeechconv4:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"Playing Baseball"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}



-(void)texttospeechconv5:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"I LOVE TO WORK FOR MY MASTER"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}
-(void)texttospeechconv6:(NSString *)command{
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    
    NSString *messageBody = [NSString stringWithFormat:@"NOPE NOT AT ALL"];
    
    //////////
    
    NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
    
    NSLog(@"url is: %@",url);
    
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
        
        
        
        NSLog(@"NSObject: %@", responseObject);
        
        NSData *audioData = responseObject;
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
        
        [self->_audioPlayer prepareToPlay];
        [self->_audioPlayer play];
        
        // NSLog(@"responseString: %@", responseString);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];
    
    
}


//weather
- (IBAction)clickMeButton:(id)sender {

    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    NSString *sentense = [_enterCity.text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    NSString *url = [NSString stringWithFormat:@"%sq=%@", BASE_URL1, sentense];
    
    
    [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"JSON: %@", responseObject);
        
        NSDictionary *details = [responseObject objectForKey:@"main"];
        NSString *temp = [details objectForKey:@"temp"];
        NSString *temp_min = [details objectForKey:@"temp_min"];
        
        
        //   NSArray *array=[responseObject objectForKey:@"weather"];
        // NSDictionary *details2=[array objectAtIndex:0];
        //  NSString *description=[details2 objectForKey:@"description"];
        
        NSLog(@"temp: %@", temp);
        NSLog(@"temp_min:%@", temp_min);
        
        NSString *messageBody = [NSString stringWithFormat:@"temp: %@,@temp_min: %@", temp, temp_min];
        
        //////////
        
        NSString *sentence = [messageBody stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        
        
        NSString *url = [NSString stringWithFormat:@"%sq=%@",BASE_URL2 , sentence];
        
        NSLog(@"url is: %@",url);
        
        manager.responseSerializer = [AFHTTPResponseSerializer serializer];
        [manager GET:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
            
            operation.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"audio/mpeg",nil];
            
            
            
            NSLog(@"NSObject: %@", responseObject);
            
            NSData *audioData = responseObject;
            
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            
            self->_audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:nil]; // audioPlayer must be a strong property. Do not create it locally
            
            [self->_audioPlayer prepareToPlay];
            [self->_audioPlayer play];
            
            // NSLog(@"responseString: %@", responseString);
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"Error: %@", error);
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                            message:[error description]
                                                           delegate:nil
                                                  cancelButtonTitle:@"Ok"
                                                  otherButtonTitles:nil, nil];
            [alert show];
        }];
        
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:[error description]
                                                       delegate:nil
                                              cancelButtonTitle:@"Ok"
                                              otherButtonTitles:nil, nil];
        [alert show];
    }];

    
    
    
}


-(void)makecall:(NSString *)command{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"tel:9133753145"]];
}

-(void)playMusic:(NSString *)command{
    NSString *audioFilePath = [[NSBundle mainBundle] pathForResource:@"mission_imposible" ofType:@"wav"];
    NSURL *pathAsURL = [[NSURL alloc] initFileURLWithPath:audioFilePath];
    
    // Init the audio player.
    NSError *error;
    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:pathAsURL error:&error];
    //[_player setDelegate:self];
    
    // Check out what's wrong in case that the player doesn't init.
    if (error) {
        NSLog(@"%@", [error localizedDescription]);
    }
    else{
        // If everything is fine, just play.
        //_player.numberOfLoops=1;
        [_player prepareToPlay];
        [_player play];
        //[lblStatus setText:@"Now playing..."];
    }

}

-(void)showPicker:(NSString *)command{
 
 ABPeoplePickerNavigationController *picker =
 [[ABPeoplePickerNavigationController alloc] init];

 //picker.peoplePickerDelegate = self;
 
 [self presentModalViewController:picker animated:YES];

 }

 - (void)peoplePickerNavigationControllerDidCancel:
 (ABPeoplePickerNavigationController *)peoplePicker
 {
 [self dismissModalViewControllerAnimated:YES];
 }

#pragma mark -
#pragma mark Socket

- (void)toggleSocketState
{
    if(!isRunning)
    {
        NSError *error = nil;
        if(![listenSocket acceptOnPort:PORT error:&error])
        {
            [self log:FORMAT(@"Error starting server: %@", error)];
            return;
        }
        
        [self log:FORMAT(@"Echo server started on port %hu", [listenSocket localPort])];
        isRunning = YES;
    }
    else
    {
        // Stop accepting connections
        [listenSocket disconnect];
        
        // Stop any client connections
        @synchronized(connectedSockets)
        {
            NSUInteger i;
            for (i = 0; i < [connectedSockets count]; i++)
            {
                // Call disconnect on the socket,
                // which will invoke the socketDidDisconnect: method,
                // which will remove the socket from the list.
                [[connectedSockets objectAtIndex:i] disconnect];
            }
        }
        
        [self log:@"Stopped Echo server"];
        isRunning = false;
    }
}

- (void)log:(NSString *)msg {
    NSLog(@"%@", msg);
}

- (NSString *)getIPAddress
{
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if( temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}

#pragma mark -
#pragma mark GCDAsyncSocket Delegate

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    // This method is executed on the socketQueue (not the main thread)
    
    @synchronized(connectedSockets)
    {
        [connectedSockets addObject:newSocket];
    }
    
    NSString *host = [newSocket connectedHost];
    UInt16 port = [newSocket connectedPort];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            
            [self log:FORMAT(@"Accepted client %@:%hu", host, port)];
            
        }
    });
    
    NSString *welcomeMsg = @"Welcome to the AsyncSocket Echo Server\r\n";
    NSData *welcomeData = [welcomeMsg dataUsingEncoding:NSUTF8StringEncoding];
    
    [newSocket writeData:welcomeData withTimeout:-1 tag:WELCOME_MSG];
    
    
    [newSocket readDataWithTimeout:READ_TIMEOUT tag:0];
    newSocket.delegate = self;
    
    //    [newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:READ_TIMEOUT tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    // This method is executed on the socketQueue (not the main thread)
    
    if (tag == ECHO_MSG)
    {
        [sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:100 tag:0];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    
    NSLog(@"== didReadData %@ ==", sock.description);
    
    NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    [self log:msg];
    [self perform:msg];
    [sock readDataWithTimeout:READ_TIMEOUT tag:0];
    [self performNLP:msg];
}

/**
 * This method is called if a read has timed out.
 * It allows us to optionally extend the timeout.
 * We use this method to issue a warning to the user prior to disconnecting them.
 **/
- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                 elapsed:(NSTimeInterval)elapsed
               bytesDone:(NSUInteger)length
{
    if (elapsed <= READ_TIMEOUT)
    {
        NSString *warningMsg = @"Are you still there?\r\n";
        NSData *warningData = [warningMsg dataUsingEncoding:NSUTF8StringEncoding];
        
        [sock writeData:warningData withTimeout:-1 tag:WARNING_MSG];
        
        return READ_TIMEOUT_EXTENSION;
    }
    
    return 0.0;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    if (sock != listenSocket)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [self log:FORMAT(@"Client Disconnected")];
            }
        });
        
        @synchronized(connectedSockets)
        {
            [connectedSockets removeObject:sock];
        }
    }
}


-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{
    [_audioPlayer stop];
    [_audioPlayer prepareToPlay];
}
@end
