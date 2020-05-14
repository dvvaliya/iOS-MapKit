//
//  ViewController.m
//  WalkTracker
//
//  Created by Dharmendra Valiya on 05/14/20.
//  Copyright © 2020 Dharmendra Valiya. All rights reserved.
//

#import "CurrentLocationViewController.h"

@interface CurrentLocationViewController ()

@property (nonatomic, strong) CLLocation * previousLocation;
@property (nonatomic, strong) NSDate * locationManagerStartDate;

@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UILabel *speedLabel;
@property (weak, nonatomic) IBOutlet UILabel *distanceLabel;
@property (weak, nonatomic) IBOutlet UILabel *headingLabel;
@property (weak, nonatomic) IBOutlet UIButton *startStopButton;
@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UISegmentedControl *mapTypeSegmentedControl;

@property (nonatomic, strong) MKDistanceFormatter * distanceFormatter;

@property (nonatomic, strong) NSTimer * timer;
@property (nonatomic, strong) NSDateComponentsFormatter * dateComponentsFormatter;
@property (nonatomic, strong) NSDateFormatter * dateFormatter;

@property (nonatomic, strong) CLLocationManager * locationManager;
@property (nonatomic, strong) NSMutableArray * locationsArray;

@property (nonatomic, strong) NSArray * directionsArray;

@property BOOL deferUpdates;
@property int totalDistance;
@property bool startedWalk;

@end

@implementation CurrentLocationViewController 

- (void)viewDidLoad {
  [super viewDidLoad];
  
  // Do any additional setup after loading the view, typically from a nib.
  self.dateComponentsFormatter = [[NSDateComponentsFormatter alloc] init];
  self.dateComponentsFormatter.allowedUnits = (NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond);
  self.dateComponentsFormatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorPad;
  
  self.dateFormatter = [[NSDateFormatter alloc] init];
  self.dateFormatter.dateStyle = NSDateFormatterNoStyle;
  self.dateFormatter.timeStyle = NSDateFormatterShortStyle;
  
  self.distanceFormatter = [[MKDistanceFormatter alloc] init];
  self.distanceFormatter.unitStyle = MKDistanceFormatterUnitStyleAbbreviated;
  
  self.directionsArray = @[@"N", @"NE", @"E", @"SE", @"S", @"SW", @"W", @"NW", @"N"];
  
  self.mapView.delegate = self;
  
  [self.mapView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPress:)]];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

- (IBAction)start:(id)sender {
  
  if (self.startedWalk)
  {
    [self.startStopButton setTitle:@"Start" forState:UIControlStateNormal];
    [self stopWalk];
  }
  else
  {
    [self.startStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    [self startWalk];
  }
}

- (void)startWalk {
  self.totalDistance = 0;
  self.locationsArray = [NSMutableArray array];
  self.startedWalk = YES;
  
  self.locationManager = [[CLLocationManager alloc] init];
  self.locationManager.delegate = self;
  [self.locationManager requestAlwaysAuthorization];
}

- (void)stopWalk {
  [self.locationManager stopUpdatingLocation];
  [self.locationManager stopUpdatingHeading];
  
  [self.timer invalidate];
  self.timer = nil;
  self.startedWalk = NO;
  
  // Add pin at last know location.
  CLLocation * lastLocation = self.locationsArray.lastObject;
  MKPointAnnotation * annotation = [[MKPointAnnotation alloc] init];
  annotation.title = @"End";
  annotation.coordinate = lastLocation.coordinate;
  annotation.subtitle = [self.dateFormatter stringFromDate: lastLocation.timestamp];
  
  [self.mapView addAnnotation:annotation];
  
  UIAlertController * successAlert = [UIAlertController
                                      alertControllerWithTitle:@"Share"
                                      message:@"Do you want to share your walk?"
                                      preferredStyle:UIAlertControllerStyleActionSheet];
  
  if ([MFMessageComposeViewController canSendAttachments])
  {
    [successAlert addAction: [UIAlertAction
                              actionWithTitle:NSLocalizedString(@"Message Trip", @"Message Trip")
                              style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction * action) {
                                [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
                                
                                [self getTripImage:^(UIImage * image) {
                                  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                  [self shareByMessages:image];
                                }];
                              }]];
  }
  
  [successAlert addAction: [UIAlertAction
                            actionWithTitle:NSLocalizedString(@"Save Trip to Photos", @"Save Trip to Photos")
                            style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction * action) {
                              [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
                              
                              [self getTripImage:^(UIImage * image) {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
                                [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                [self.navigationController popToRootViewControllerAnimated:YES];
                              }];
                            }]];
  
  [successAlert addAction: [UIAlertAction
                            actionWithTitle:NSLocalizedString(@"No Thanks", @"No Thanks")
                            style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction * action) {
                              [self.navigationController popToRootViewControllerAnimated:YES];
                            }]];
  
  [self presentViewController:successAlert animated:YES completion:nil];
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  if(status == kCLAuthorizationStatusAuthorizedAlways)
  {
    self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
    self.locationManager.activityType = CLActivityTypeFitness;
    self.locationManager.distanceFilter = kCLDistanceFilterNone;
    self.locationManager.pausesLocationUpdatesAutomatically = YES;
    
    self.locationManagerStartDate = [NSDate date];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(timerTick:)
                                                userInfo:nil
                                                 repeats:YES];
    
    [self.locationManager startUpdatingLocation];
    
    [self.locationManager startUpdatingHeading];
    
    self.mapView.showsUserLocation = YES;
  }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
  CLLocation * location = [locations lastObject];
  
  if ([self shouldUsePoint:location])
  {
    if (self.locationsArray.count > 0)
    {
      CLLocation * lastLocation = [self.locationsArray lastObject];
      int distanceTraveled = [lastLocation distanceFromLocation:location];
      self.totalDistance += distanceTraveled;
      
      CLLocationCoordinate2D * pointsCoordinate = (CLLocationCoordinate2D *)malloc(sizeof(CLLocationCoordinate2D) * 2);
      
      pointsCoordinate[0] = lastLocation.coordinate;
      pointsCoordinate[1] = location.coordinate;
      
      MKPolyline * line = [MKPolyline polylineWithCoordinates:pointsCoordinate count:2];
      [self.mapView addOverlay:line];
      
      [self.mapView setCenterCoordinate:location.coordinate animated:NO];
    }
    else
    {
      [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(location.coordinate, 400, 400) animated:NO];
      
      // First coordinate. Set the start pin.
      MKPointAnnotation * annotation = [[MKPointAnnotation alloc] init];
      annotation.coordinate = location.coordinate;
      annotation.title = @"Start";
      annotation.subtitle = [self.dateFormatter stringFromDate: location.timestamp];
      [self.mapView addAnnotation:annotation];
    }
    
    self.distanceLabel.text = [self.distanceFormatter stringFromDistance:self.totalDistance];
    
    int metersPerHour = location.speed * 60 * 60;
    
    self.speedLabel.text = [NSString stringWithFormat:@"%@ / h", [self.distanceFormatter stringFromDistance:metersPerHour]];
    
    [self.locationsArray addObject:location];
    
    if(!self.deferUpdates && [CLLocationManager deferredLocationUpdatesAvailable])
    {
      CLLocationDistance distance = 25;
      NSTimeInterval timeInterval = 60 * 5;
      [self.locationManager allowDeferredLocationUpdatesUntilTraveled:distance timeout:timeInterval];
      self.deferUpdates = YES;
    }
  }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
  CLLocationDirection heading;
  if (newHeading.trueHeading > 0)
  {
    heading = newHeading.trueHeading;
  }
  else
  {
    heading = newHeading.magneticHeading;
  }
  
  self.headingLabel.text = [NSString stringWithFormat:@"%@ (%d\u00B0)", [self getDirectionFromHeading:heading], (int)heading];
}

- (void)timerTick:(NSTimer *)timer
{
  NSTimeInterval timeInterval = fabs([self.locationManagerStartDate timeIntervalSinceNow]);
  
  self.timeLabel.text = [self.dateComponentsFormatter stringFromTimeInterval:timeInterval];
}

- (NSString *)getDirectionFromHeading:(CLLocationDirection)heading {
  int directionIndex = (int)floor(((int)(heading + 22.5) % 360) / 45);
  return [self.directionsArray objectAtIndex:directionIndex];
}

- (BOOL)shouldUsePoint:(CLLocation *)location {
  BOOL shouldUse = YES;
  
  NSTimeInterval secondsSinceManagerStarted = [location.timestamp timeIntervalSinceDate:self.locationManagerStartDate];
  
  if((location.horizontalAccuracy > 15) || (location.horizontalAccuracy <= 0))
  {
    shouldUse = NO;
  }
  else if(secondsSinceManagerStarted < 0)
  {
    shouldUse = NO;
  }
  
  return shouldUse;
}

- (void)locationManager:(CLLocationManager *)manager didFinishDeferredUpdatesWithError:(NSError *)error {
  self.deferUpdates = NO;
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
  
  // If current location is user location, we want to keep the default behavior.
  if ([annotation isKindOfClass:[MKUserLocation class]])
  {
    return nil;
  }
  
  // First try to dequeue an existing annotation object.
  MKAnnotationView * pinView = [mapView dequeueReusableAnnotationViewWithIdentifier:@"pinView"];
  
  // If there was nothing to dequeue, create a new pin annotation view.
  if (!pinView)
  {
    pinView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"pinView"];
  }
  
  if ([annotation.title isEqualToString:@"Start"])
  {
    pinView.image = [UIImage imageNamed:@"Location_Green"];
    
    UIImageView * leftImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Running_Green"]];
    pinView.leftCalloutAccessoryView = leftImageView;
    pinView.canShowCallout = YES;
  }
  else if ([annotation.title isEqualToString:@"End"])
  {
    pinView.image = [UIImage imageNamed:@"Location_Plum"];
    
    UIImageView * leftImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Standing_Plum"]];
    pinView.leftCalloutAccessoryView = leftImageView;
    pinView.canShowCallout = YES;
  }
  else
  {
    pinView.image = [UIImage imageNamed:@"Location_Blue"];
    pinView.draggable = YES;
  }
  
  pinView.centerOffset = CGPointMake(0, -pinView.image.size.height / 2);
  return pinView;
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
  MKPolylineRenderer * polylineRenderer = [[MKPolylineRenderer alloc] initWithOverlay:overlay];
  
  polylineRenderer.strokeColor = [UIColor colorWithRed:240/255. green:90/255. blue:40/255. alpha:1.0];
  polylineRenderer.lineWidth = 5.0;
  polylineRenderer.alpha = 0.5;
  return polylineRenderer;
}

- (void)mapLongPress:(UIGestureRecognizer *)gestureRecognizer {
  
  if (gestureRecognizer.state == UIGestureRecognizerStateBegan)
  {
    CGPoint mapPoint = [gestureRecognizer locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:mapPoint
                                              toCoordinateFromView:self.mapView];
  
    MKPointAnnotation * annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = coordinate;
    [self.mapView addAnnotation:annotation];
  }
}

- (void)getTripImage:(void(^)(UIImage *))imageComplete {
  // Get the polyline to draw
  CLLocationCoordinate2D clCoorindates[self.locationsArray.count];
  
  for (int index = 0; index < self.locationsArray.count; index++)
  {
    CLLocation * location = [self.locationsArray objectAtIndex:index];
    clCoorindates[index] = location.coordinate;
  }
  
  MKPolyline * path = [MKPolyline polylineWithCoordinates:clCoorindates count:self.locationsArray.count];
  MKMapRect boundingRect = path.boundingMapRect;
  
  //Add padding to the region
  int wPadding = boundingRect.size.width * 0.25;
  int hPadding = boundingRect.size.height * 0.25;
  
  boundingRect.size.width += wPadding;
  boundingRect.size.height += hPadding;
  
  //Center the region on the line
  boundingRect.origin.x -= wPadding / 2;
  boundingRect.origin.y -= hPadding / 2;
  
  MKMapSnapshotOptions *options = [[MKMapSnapshotOptions alloc]init];
  options.region = MKCoordinateRegionForMapRect(boundingRect);
  options.mapType = MKMapTypeStandard;
  options.showsBuildings = NO;
  options.showsPointsOfInterest = NO;
  options.size = self.view.frame.size;
  
  MKMapSnapshotter *snapshotter = [[MKMapSnapshotter alloc] initWithOptions:options];
  
  [snapshotter startWithCompletionHandler:^(MKMapSnapshot *snapshot, NSError *error) {
    
    if (error == nil)
    {
      UIImage * mapWithPath = nil;
      UIImage * image = snapshot.image;
      
      UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
      [image drawAtPoint:CGPointMake(0, 0)];
      
      CGContextRef context = UIGraphicsGetCurrentContext();
      
      // Draw the path
      CGContextSetStrokeColorWithColor(context, [[UIColor colorWithRed:240/255. green:90/255. blue:40/255. alpha:1.0] CGColor]);
      CGContextSetLineWidth(context,5.0f);
      CGContextBeginPath(context);
      
      CLLocationCoordinate2D coordinates[[path pointCount]];
      [path getCoordinates:coordinates range:NSMakeRange(0, [path pointCount])];
      
      for (int i = 0; i < [path pointCount]; i++)
      {
        CGPoint point = [snapshot pointForCoordinate:coordinates[i]];
        
        if (i == 0)
        {
          CGContextMoveToPoint(context,point.x, point.y);
        }
        else
        {
          CGContextAddLineToPoint(context,point.x, point.y);
          
        }
      }
      
      CGContextStrokePath(context);
      
      // Draw the annotations.
      MKAnnotationView * startPinView = [[MKAnnotationView alloc] init];
      startPinView.image = [UIImage imageNamed:@"Location_Green"];
      startPinView.centerOffset = CGPointMake(0, -startPinView.image.size.height / 2);
      
      MKAnnotationView * endPinView = [[MKAnnotationView alloc] init];
      endPinView.image = [UIImage imageNamed:@"Location_Plum"];
      endPinView.centerOffset = CGPointMake(0, -startPinView.image.size.height / 2);
      
      for (MKPointAnnotation * annotation in self.mapView.annotations) {
        CGPoint mapPoint = [snapshot pointForCoordinate:annotation.coordinate];
        
        MKAnnotationView * viewForAnnotation = nil;
        if ([annotation.title isEqualToString:@"Start"])
        {
          viewForAnnotation = startPinView;
        }
        else if ([annotation.title isEqualToString:@"End"])
        {
          viewForAnnotation = endPinView;
        }
          
        if (viewForAnnotation)
        {
          mapPoint.x = mapPoint.x + viewForAnnotation.centerOffset.x - (viewForAnnotation.bounds.size.width / 2);
          mapPoint.y = mapPoint.y + viewForAnnotation.centerOffset.y - (viewForAnnotation.bounds.size.height / 2);
            
          [viewForAnnotation.image drawAtPoint:mapPoint];
        }
      }
      
      mapWithPath = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();
      imageComplete(mapWithPath);
    }
  }];
  
}

- (void)shareByMessages:(UIImage *)mapImage {
  NSString * body = @"Check out the walk I did today.";
  
  MFMessageComposeViewController * messageViewController = [MFMessageComposeViewController new];
  messageViewController.messageComposeDelegate = self;
  messageViewController.body = body;
  
  NSData * imageData = UIImagePNGRepresentation(mapImage);
  [messageViewController addAttachmentData:imageData typeIdentifier:@"image/jpeg" filename:@"myWalk.jpg"];
  
  [self presentViewController:messageViewController animated:YES completion:^(){
  }];
}

-(void)messageComposeViewController:(MFMessageComposeViewController *)controller didFinishWithResult:(MessageComposeResult)result {
  [self dismissViewControllerAnimated:controller completion:nil];
}

- (IBAction)mapTypeChanged:(id)sender {
  switch (self.mapTypeSegmentedControl.selectedSegmentIndex) {
    case 0:
      // Standard Map
      self.mapView.mapType = MKMapTypeStandard;
      self.mapTypeSegmentedControl.tintColor = [UIColor darkGrayColor];
      break;
    case 1:
      // Hybrid
      self.mapView.mapType = MKMapTypeHybrid;
      self.mapTypeSegmentedControl.tintColor = [UIColor whiteColor];
      break;
  }
  
}

@end
