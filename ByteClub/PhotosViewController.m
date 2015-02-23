//
//  PhotosViewController.m
//  ByteClub
//
//  Created by Charlie Fulton on 7/28/13.
//  Copyright (c) 2013 Razeware. All rights reserved.
//

#import "PhotosViewController.h"
#import "PhotoCell.h"
#import "Dropbox.h"
#import "DBFile.h"

@interface PhotosViewController ()<UITableViewDelegate,UITableViewDataSource,UIImagePickerControllerDelegate,UINavigationControllerDelegate, NSURLSessionTaskDelegate>

@property (weak, nonatomic) IBOutlet UIProgressView *progress;
@property (weak, nonatomic) IBOutlet UIView *uploadView;
@property (weak, nonatomic) IBOutlet UITableView *tableView;

@property (nonatomic, strong) NSArray *photoThumbnails;


@property (nonatomic, strong) NSURLSession *session;

@property (nonatomic, strong) NSURLSessionUploadTask *uploadTask;

@end

@implementation PhotosViewController

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        // 1
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        
        // 2
        [config setHTTPAdditionalHeaders:@{@"Authorization": [Dropbox apiAuthorizationHeader]}];
        
        // 3
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    [self refreshPhotos];
}

- (void)refreshPhotos
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    NSString *photoDir = [NSString stringWithFormat:@"https://api.dropbox.com/1/search/dropbox/%@/photos?query=.jpg", appFolder];
    NSURL *url = [NSURL URLWithString:photoDir];
    NSURLSessionDataTask *dataTask = [self.session
                                      dataTaskWithURL:url
                                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                          if (!error) {
                                              NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                                              if (httpResponse.statusCode == 200) {
                                                  NSError *jsonError;
                                                  NSArray *filesJSON = [NSJSONSerialization
                                                                        JSONObjectWithData:data
                                                                        options:NSJSONReadingAllowFragments
                                                                        error:&jsonError];
                                                  NSMutableArray *dbFiles = [[NSMutableArray alloc] init];
                                                  if (!jsonError) {
                                                      for (NSDictionary *fileMetaData in filesJSON) {
                                                          DBFile *file = [[DBFile alloc] initWithJSONData:fileMetaData];
                                                          [dbFiles addObject:file];
                                                      }
                                                      [dbFiles sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                          return [obj1 compare:obj2];
                                                      }];
                                                      self.photoThumbnails = dbFiles;
                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                          [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                                                          [self.tableView reloadData];
                                                      });
                                                  }
                                              }else{
                                                  
                                              }
                                          }else{
                                              
                                          }
    }];
    [dataTask resume];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - UITableViewDatasource and UITableViewDelegate methods


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    return [_photoThumbnails count];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
   
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"PhotoCell";
    PhotoCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    DBFile *photo = _photoThumbnails[indexPath.row];
    
    if (!photo.thumbNail) {
        // only download if we are moving
        if (self.tableView.dragging == NO && self.tableView.decelerating == NO)
        {
            if(photo.thumbExists) {
                NSString *urlString = [NSString stringWithFormat:@"https://api-content.dropbox.com/1/thumbnails/dropbox%@?size=xl",photo.path];
                NSString *encodedUrl = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                NSURL *url = [NSURL URLWithString:encodedUrl];
                NSLog(@"logging this url so no warning in starter project %@",url);
                
                // GO GET THUMBNAILS //
                [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
                NSURLSessionDataTask *dataTask = [self.session
                                                  dataTaskWithURL:url
                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                      if (!error) {
                                                          UIImage *image = [UIImage imageWithData:data];
                                                          photo.thumbNail = image;
                                                          dispatch_async(dispatch_get_main_queue(), ^{
                                                              [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                                                              cell.thumbnailImage.image = photo.thumbNail;
                                                              
                                                          });
                                                      }else{
                                                          
                                                      }
                }];
                [dataTask resume];
                
                
                
            }
        }
    }
    
    // Configure the cell...
    return cell;
}

- (IBAction)choosePhoto:(UIBarButtonItem *)sender
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate methods
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [self dismissViewControllerAnimated:YES completion:nil];
    [self uploadImage:image];
}

// stop upload
- (IBAction)cancelUpload:(id)sender
{
    if (self.uploadTask.state == NSURLSessionTaskStateRunning) {
        [self.uploadTask cancel];
    }
}

- (void)uploadImage:(UIImage*)image
{
    NSData *imageData = UIImageJPEGRepresentation(image, 0.6);
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfiguration.HTTPMaximumConnectionsPerHost = 1;
    [sessionConfiguration setHTTPAdditionalHeaders:@{@"Authorization": [Dropbox apiAuthorizationHeader]}];
    NSURLSession *uploadSession = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
    NSURL *url = [Dropbox createPhotoUploadURL];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPMethod:@"PUT"];
    self.uploadTask = [uploadSession uploadTaskWithRequest:request fromData:imageData];
    self.uploadView.hidden = NO;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [self.uploadTask resume];
    
}

#pragma mark - NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progress setProgress:totalBytesSent * 1.0 / totalBytesExpectedToSend animated:YES];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        self.uploadView.hidden = YES;
        [self.progress setProgress:0.5];
    });
    
    if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshPhotos];
        });
    }else{
        
    }
}


@end
