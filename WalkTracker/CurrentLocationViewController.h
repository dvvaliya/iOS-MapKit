//
//  ViewController.h
//  WalkTracker
//
//  Created by Dharmendra Valiya on 05/14/20.
//  Copyright © 2020 Dharmendra Valiya. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <MessageUI/MessageUI.h>

@interface CurrentLocationViewController : UIViewController  <CLLocationManagerDelegate, MKMapViewDelegate, MFMessageComposeViewControllerDelegate>


@end

