/**
 * Copyright (c) 2018 TomTom N.V. All rights reserved.
 *
 * This software is the proprietary copyright of TomTom N.V. and its subsidiaries and may be used
 * for internal evaluation purposes or commercial use strictly subject to separate licensee
 * agreement between you and TomTom. If you are the licensee, you are only permitted to use
 * this Software in accordance with the terms of your license agreement. If you are not the
 * licensee then you are not authorised to use this software in any manner and should
 * immediately return it to TomTom N.V.
 */

#import "RouteMatchingViewController.h"
#import <TomTomOnlineSDKMapsDriving/TomTomOnlineSDKMapsDriving.h>

@interface RouteMatchingViewController () <TTAnnotationDelegate, TTMapViewDelegate, TTMatcherDelegate, TTRouteResponseDelegate>

@property (nonatomic, strong) DrivingSource *source;
@property (nonatomic, strong) TTMatcher *matcher;
@property (nonatomic, assign) BOOL startSending;

@property (nonatomic, strong) TTChevronObject *chevron;
@property (nonatomic, strong) TTMapRoute *route;
@property (nonatomic, strong) TTRoute *routePlanner;

@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic) CLLocationCoordinate2D *waypoints;

@end

@implementation RouteMatchingViewController

- (void)setupCenterOnWillHappen {
    [self.mapView centerOnCoordinate:TTCoordinate.LODZ withZoom:10];
}

- (void)onMapReady {
    self.mapView.annotationManager.delegate = self;
    [self createChevron];
    [self createRoute];
    self.mapView.maxZoom = TTMapZoom.MAX;
    self.mapView.minZoom = TTMapZoom.MIN;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.routePlanner = [[TTRoute alloc] init];
    self.routePlanner.delegate = self;
    self.waypoints = malloc(sizeof(CLLocationCoordinate2D) * 3);
    self.waypoints[0] = [TTCoordinate LODZ_SREBRZYNSKA_WAYPOINT_A];
    self.waypoints[1] = [TTCoordinate LODZ_SREBRZYNSKA_WAYPOINT_B];
    self.waypoints[2] = [TTCoordinate LODZ_SREBRZYNSKA_WAYPOINT_C];
    self.mapView.delegate = self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.timer invalidate];
    free(self.waypoints);
}

- (void)createChevron {
    [self.mapView setShowsUserLocation:false];
    self.chevron = [[TTChevronObject alloc] initWithNormalImage:[TTChevronObject defaultNormalImage] withDimmedImage:[TTChevronObject defaultDimmedImage]];
}

- (void)createRoute {
    [self.progress show];
    TTRouteQuery *query = [[[TTRouteQueryBuilder createWithDest:TTCoordinate.LODZ_SREBRZYNSKA_STOP andOrig:TTCoordinate.LODZ_SREBRZYNSKA_START] withWayPoints:self.waypoints count:3] build];
    [self.routePlanner planRouteWithQuery:query];
}

- (void)start {
    [self.mapView.trackingManager addTrackingObject:self.chevron];
    [self.mapView.trackingManager startTrackingObject:self.chevron];
    self.source = [[DrivingSource alloc] initWithTrackingManager:self.mapView.trackingManager trackingObject:self.chevron];
    [self.source activate];

    TTCameraPosition *camera = [[[[[[TTCameraPositionBuilder createWithCameraPosition:[TTCoordinate LODZ_SREBRZYNSKA_START]]
                                    withAnimationDuration:[TTCamera ANIMATION_TIME]]
                                   withBearing:[TTCamera BEARING_START]]
                                  withPitch:[TTCamera DEFAULT_MAP_PITCH_FLAT]]
                                 withZoom:17]
                                build];

    [self.mapView setCameraPosition:camera];
}

- (void)matcher:(ProviderLocation *)providerLocation {
    TTMatcherLocation *location = [[TTMatcherLocation alloc] initWithCoordinate:providerLocation.coordinate withBearing:providerLocation.bearing withBearingValid:YES withEPE:0.0 withSpeed:providerLocation.speed withDuration:providerLocation.timestamp];
    [self.matcher setMatcherLocation:location];
}

- (void)matcherResultMatchedLocation:(TTMatcherLocation *)matched withOriginalLocation:(TTMatcherLocation *)original isMatched:(BOOL)isMatched {
    [self drawRedCircle:original.coordinate];
    TTLocation *location = [[TTLocation alloc] initWithCoordinate:matched.coordinate withRadius:matched.radius withBearing:matched.bearing withAccuracy:0.0 isDimmed:!isMatched];
    [self.source updateLocationWithLocation: location];
    [self.chevron setHidden:NO];
}

- (void)drawRedCircle:(CLLocationCoordinate2D)coordinate {
    [self.mapView.annotationManager removeAllOverlays];
    TTCircle *circle = [TTCircle circleWithCenterCoordinate:coordinate radius:2 width:1 color:[UIColor redColor] fill:YES colorOutlet:[UIColor redColor]];
    [self.mapView.annotationManager addOverlay:circle];
}

- (void)sendingLocation:(TTFullRoute *)fullRoute {
    __block int index = 0;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:true block:^(NSTimer * _Nonnull timer) {
        index++;

        if (index == fullRoute.coordinatesData.count) {
            index = 0;
        }

        if (index - 1 < 0) {
            return;
        }

        CLLocationCoordinate2D prevCoordiante = [LocationUtils coordinateForValueWithValue:[fullRoute.coordinatesData objectAtIndex:(index - 1)]];
        CLLocationCoordinate2D nextCoordinate = [LocationUtils coordinateForValueWithValue:[fullRoute.coordinatesData objectAtIndex:index]];
        double bearing = [LocationUtils bearingWithCoordinateWithCoordinate:nextCoordinate prevCoordianate:prevCoordiante];
        nextCoordinate = [RandomizeCoordinate interpolateWithCoordinate:nextCoordinate];
        ProviderLocation *providerLocation = [[ProviderLocation alloc] initWithCoordinate:nextCoordinate withRadius:0.0 withBearing:bearing withAccuracy:0.0 isDimmed:YES];
        providerLocation.timestamp = [NSDate new].timeIntervalSince1970;
        providerLocation.speed = 5.0;
        [self matcher:providerLocation];
    }];
}

#pragma mark TTRouteResponseDelegate

- (void)route:(TTRoute *)route completedWithResult:(TTRouteResult *)result {
    TTFullRoute *plannedRoute = result.routes.firstObject;
    if(!plannedRoute) {
        return;
    }
    TTMapRoute *mapRoute = [TTMapRoute routeWithCoordinatesData:result.routes.firstObject withRouteStyle:TTMapRouteStyle.defaultActiveStyle
                                                     imageStart:TTMapRoute.defaultImageDeparture imageEnd:TTMapRoute.defaultImageDestination];
    [self.mapView.routeManager addRoute:mapRoute];
    [self.mapView.routeManager bringToFrontRoute:mapRoute];
    [self.etaView showWithSummary:plannedRoute.summary style:ETAViewStylePlain];
    [self.progress hide];
    
    self.matcher = [[TTMatcher alloc] initWithMatchDataSet:plannedRoute];
    self.matcher.delegate = self;
    [self start];
    [self sendingLocation:plannedRoute];
}

- (void)route:(TTRoute *)route completedWithResponseError:(TTResponseError *)responseError {
    [self handleError:responseError];
}

@end