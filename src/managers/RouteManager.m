//
//  RouteModel.m
//  CycleStreets
//
//  Created by neil on 22/03/2011.
//  Copyright 2011 CycleStreets Ltd. All rights reserved.
//

#import "RouteManager.h"
#import "BUNetworkOperation.h"
#import "GlobalUtilities.h"
#import "CycleStreets.h"
#import "AppConstants.h"
#import "Files.h"
#import "HudManager.h"
#import "BUResponseObject.h"
#import "BUNetworkOperation.h"
#import "SettingsManager.h"
#import "SavedRoutesManager.h"
#import "RouteVO.h"
#import <MapKit/MapKit.h>
#import "UserLocationManager.h"
#import "WayPointVO.h"
#import "ApplicationXMLParser.h"
#import "BUDataSourceManager.h"
#import "LeisureRouteVO.h"
#import <NSObject+BKBlockExecution.h>

static NSString *const LOCATIONSUBSCRIBERID=@"RouteManager";


@interface RouteManager()



@end

static NSString *useDom = @"1";


@implementation RouteManager
SYNTHESIZE_SINGLETON_FOR_CLASS(RouteManager);


//=========================================================== 
// - (id)init
//
//=========================================================== 
- (instancetype)init
{
    self = [super init];
    if (self) {
        self.routes = [[NSMutableDictionary alloc]init];
		self.activeRouteDir=OLDROUTEARCHIVEPATH;
		[self evalRouteArchiveState];
    }
    return self;
}




//
/***********************************************
 * @description		NOTIFICATIONS
 ***********************************************/
//

-(void)listNotificationInterests{
	
	BetterLog(@"");
	
	[notifications addObject:REQUESTDIDCOMPLETEFROMSERVER];
	[notifications addObject:DATAREQUESTFAILED];
	[notifications addObject:REMOTEFILEFAILED];
	[notifications addObject:REQUESTDIDFAIL];
	[notifications addObject:XMLPARSERDIDFAILPARSING];
	[notifications addObject:JSONPARSERDIDFAILPARSING];
	
	[notifications addObject:GPSLOCATIONCOMPLETE];
	[notifications addObject:GPSLOCATIONUPDATE];
	[notifications addObject:GPSLOCATIONFAILED];
	
	
	[self addRequestID:CALCULATEROUTE];
	[self addRequestID:RETRIEVEROUTEBYID];
	[self addRequestID:UPDATEROUTE];
	[self addRequestID:LEISUREROUTE];
	
	[super listNotificationInterests];
	
}

-(void)didReceiveNotification:(NSNotification*)notification{
	
	[super didReceiveNotification:notification];
	NSDictionary	*dict=[notification userInfo];
	BUNetworkOperation		*response=[dict objectForKey:RESPONSE];
	
	NSString	*dataid=response.dataid;
	BetterLog(@"response.dataid=%@",response.dataid);
	
	if([self isRegisteredForRequest:dataid]){
		
		
		if([notification.name isEqualToString:REMOTEFILEFAILED] || [notification.name isEqualToString:DATAREQUESTFAILED] || [notification.name isEqualToString:REQUESTDIDFAIL]){
			[[HudManager sharedInstance] showHudWithType:HUDWindowTypeError withTitle:@"Network Error" andMessage:@"Unable to contact server"];
		}

		if([notification.name isEqualToString:XMLPARSERDIDFAILPARSING] || [notification.name isEqualToString:JSONPARSERDIDFAILPARSING]){
			[[HudManager sharedInstance] showHudWithType:HUDWindowTypeError withTitle:@"Route error" andMessage:@"Unable to load this route, please re-check route number."];
		}
		
		
	}
	
	if([[UserLocationManager sharedInstance] hasSubscriber:LOCATIONSUBSCRIBERID ]){
		
		if([notification.name isEqualToString:GPSLOCATIONCOMPLETE]){
			[self locationDidComplete:notification];
		}
		
		if([notification.name isEqualToString:GPSLOCATIONFAILED]){
			[self locationDidFail:notification];
		}
		
	}
	
	
	
	
	
}


#pragma mark - Core Location updates

-(void)locationDidFail:(NSNotification*)notification{
	
	[[UserLocationManager sharedInstance] stopUpdatingLocationForSubscriber:LOCATIONSUBSCRIBERID];
	
	[self queryFailureMessage: @"Could not plan valid route for selected waypoints."];
	
}

-(void)locationDidComplete:(NSNotification*)notification{
	
	[[UserLocationManager sharedInstance] stopUpdatingLocationForSubscriber:LOCATIONSUBSCRIBERID];
	
	CLLocation *location=(CLLocation*)[notification object];
	
	MKMapItem *source=_mapRoutingRequest.source;
	MKMapItem *destination=_mapRoutingRequest.destination;
	
	CLLocationCoordinate2D fromcoordinate=source.placemark.coordinate;
	CLLocationCoordinate2D tocoordinate=destination.placemark.coordinate;
	
	if(fromcoordinate.latitude==0.0 && fromcoordinate.longitude==0.0){
		
		[self loadRouteForCoordinates:location.coordinate to:tocoordinate];
		
	}else if(tocoordinate.latitude==0.0 && tocoordinate.longitude==0.0){
		
		[self loadRouteForCoordinates:fromcoordinate to:location.coordinate];
		
	}else{
		[self loadRouteForCoordinates:fromcoordinate to:tocoordinate];
	}
		
		
	
	
}




#pragma mark - Load Routes for items

-(void)loadRouteForEndPoints:(CLLocation*)fromlocation to:(CLLocation*)tolocation{
    
	[self loadRouteForCoordinates:fromlocation.coordinate to:tolocation.coordinate];
    
}


-(void)loadRouteForCoordinates:(CLLocationCoordinate2D)fromcoordinate to:(CLLocationCoordinate2D)tocoordinate{
	
	
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
    SettingsVO *settingsdp = [SettingsManager sharedInstance].dataProvider;
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
									 
									 [NSString stringWithFormat:@"%@,%@|%@,%@",BOX_FLOAT(fromcoordinate.longitude),BOX_FLOAT(fromcoordinate.latitude),BOX_FLOAT(tocoordinate.longitude),BOX_FLOAT(tocoordinate.latitude)],@"itinerarypoints",
                                     useDom,@"useDom",
                                     settingsdp.plan,@"plan",
                                     [settingsdp returnKilometerSpeedValue],@"speed",
                                     cycleStreets.files.clientid,@"clientid",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=CALCULATEROUTE;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
	
	__weak __typeof(&*self)weakSelf = self;
	request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[weakSelf loadRouteForEndPointsResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:@"Obtaining route from CycleStreets.net" andMessage:nil];
	
}




-(void)loadRouteForEndPointsResponse:(BUNetworkOperation*)response{
	
	BetterLog(@"");
    
    
    switch(response.responseStatus){
        
        case ValidationCalculateRouteSuccess:
		{  
			RouteVO *newroute = response.responseObject;
            
            [[SavedRoutesManager sharedInstance] addRoute:newroute toDataProvider:SAVEDROUTE_RECENTS];
                
            [self warnOnFirstRoute];
            [self selectRoute:newroute];
			[self saveRoute:_selectedRoute];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:CALCULATEROUTERESPONSE object:nil];
            
            [[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, added path to map" andMessage:nil];
        }
        break;
            
            
        case ValidationCalculateRouteFailed:
            
            [self queryFailureMessage:@"Routing error: Could not plan valid route for selected waypoints."];
            
        break;
			
		
		case ValidationCalculateRouteFailedOffNetwork:
            
            [self queryFailureMessage:@"Routing error: not all waypoints are on known cycle routes."];
            
		break;
			
		default:
			break;
        
        
    }
    

    
}


-(void)loadRouteForRouteId:(NSString*)routeid{
    
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
    SettingsVO *settingsdp = [SettingsManager sharedInstance].dataProvider;
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
                                     useDom,@"useDom",
                                     settingsdp.plan,@"plan",
                                     routeid,@"itinerary",
									 cycleStreets.files.clientid,@"clientid",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=RETRIEVEROUTEBYID;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
    request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self loadRouteForRouteIdResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
	// format routeid to decimal style ie xx,xxx,xxx
	NSNumberFormatter *currencyformatter=[[NSNumberFormatter alloc]init];
	[currencyformatter setNumberStyle:NSNumberFormatterDecimalStyle];
	NSString *result=[currencyformatter stringFromNumber:[NSNumber numberWithInt:[routeid intValue]]];

    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:[NSString stringWithFormat:@"Loading route %@ on CycleStreets",result] andMessage:nil];
}




-(void)loadRouteForRouteId:(NSString*)routeid withPlan:(NSString*)plan{
	
	
	BOOL found=[[SavedRoutesManager sharedInstance] findRouteWithId:routeid andPlan:plan];
	
	if(found==YES){
		
		RouteVO *route=[self loadRouteForFileID:[NSString stringWithFormat:@"%@_%@",routeid,plan]];
		
		[self selectRoute:route];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:NEWROUTEBYIDRESPONSE object:nil];
		
		[[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, this route is now selected." andMessage:nil];
		
	}else{
		
		NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
										 useDom,@"useDom",
										 plan,@"plan",
										 routeid,@"itinerary",
										 nil];
		
		BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
		request.dataid=RETRIEVEROUTEBYID;
		request.requestid=ZERO;
		request.parameters=parameters;
		request.source=DataSourceRequestCacheTypeUseNetwork;
		
		request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
			
			[self loadRouteForRouteIdResponse:operation];
			
		};
		
		[[BUDataSourceManager sharedInstance] processDataRequest:request];
		
		[[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:[NSString stringWithFormat:@"Searching for %@ route %@ on CycleStreets",[plan capitalizedString], routeid] andMessage:nil];
		
	}
    
	
    
}



-(void)loadRouteForRouteIdResponse:(BUNetworkOperation*)response{
	
	BetterLog(@"");
	
	switch(response.responseStatus){
			
		case ValidationCalculateRouteSuccess:
		{
			RouteVO *newroute=response.responseObject;
			
			[[SavedRoutesManager sharedInstance] addRoute:newroute toDataProvider:SAVEDROUTE_RECENTS];
			
			[self selectRoute:newroute];
			[self saveRoute:_selectedRoute ];
			
			[[NSNotificationCenter defaultCenter] postNotificationName:NEWROUTEBYIDRESPONSE object:nil];
			
			[[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, this route is now selected." andMessage:nil];
		}
			break;
			
			
		case ValidationCalculateRouteFailed:
			
			[self queryFailureMessage:@"Unable to find a route with this number."];
			
			break;
			
		default:
			break;
			
			
	}
	
	
}



//
/***********************************************
 * @description			OS6 Routing request support
 ***********************************************/
//

-(void)loadRouteForRouting:(MKDirectionsRequest*)routingrequest{
	
	MKMapItem *source=routingrequest.source;
	MKMapItem *destination=routingrequest.destination;
	
	CLLocationCoordinate2D fromlocation=source.placemark.coordinate;
	CLLocationCoordinate2D tolocation=destination.placemark.coordinate;
	
	// if a user has currentLocation as one of their pins
	// MKDirectionsRequest will return 0,0 for it
	// so we have to do another lookup in app to correct this!
	if(fromlocation.latitude==0.0 || tolocation.latitude==0.0){
		
		self.mapRoutingRequest=routingrequest;
		
		[[UserLocationManager sharedInstance] startUpdatingLocationForSubscriber:LOCATIONSUBSCRIBERID];
		
		
	}else{
		
		[self loadRouteForCoordinates:fromlocation to:tolocation];
		
	}
	
	
}



#pragma mark - Leisure routing


-(void)loadRouteForLeisure:(LeisureRouteVO*)leisureroute{
	
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	
	NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
									 leisureroute.coordinateString,@"itinerarypoints",
									 @"leisure",@"plan",
									 cycleStreets.files.clientid,@"clientid",
									 useDom,@"useDom",
									 nil];
	
	if(leisureroute.hasPOIs)
		[parameters setObject:leisureroute.poiKeys forKey:@"poitypes"];
	
	[parameters setObject:leisureroute.routeValueString forKey:leisureroute.routeType==LeisureRouteTypeDistance ? @"distance" : @"duration"];
	
	
	BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
	request.dataid=LEISUREROUTE;
	request.requestid=ZERO;
	request.parameters=parameters;
	request.source=DataSourceRequestCacheTypeUseNetwork;
	
	request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self loadRouteForLeisureResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
	[[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:@"Obtaining leisure route from CycleStreets.net" andMessage:nil];
	
}


-(void)loadRouteForLeisureResponse:(BUNetworkOperation*)response{
	
	BetterLog(@"");
	
	
	switch(response.responseStatus){
			
		case ValidationCalculateRouteSuccess:
		{
			RouteVO *newroute = response.responseObject;
			
			[[SavedRoutesManager sharedInstance] addRoute:newroute toDataProvider:SAVEDROUTE_RECENTS];
			
			[self warnOnFirstRoute];
			[self selectRoute:newroute];
			[self saveRoute:_selectedRoute];
			
			[[NSNotificationCenter defaultCenter] postNotificationName:LEISUREROUTERESPONSE object:nil];
			
			[[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:@"Found route, added path to map" andMessage:nil];
		}
			break;
			
			
		case ValidationCalculateRouteFailed:
			
			[self queryFailureMessage:@"Routing error: Could not plan valid route for selected waypoints."];
			
			break;
			
			
		case ValidationCalculateRouteFailedOffNetwork:
			
			[self queryFailureMessage:@"Routing error: not all waypoints are on known cycle routes."];
			
			break;
			
		default:
			break;
			
			
	}
	
	
	
}






#pragma mark - Waypoint requests


-(void)loadRouteForWaypoints:(NSMutableArray*)waypoints{
	
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
    SettingsVO *settingsdp = [SettingsManager sharedInstance].dataProvider;
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
									 
									 [self convertWaypointArrayforRequest:waypoints],@"itinerarypoints",
                                     useDom,@"useDom",
                                     settingsdp.plan,@"plan",
                                     [settingsdp returnKilometerSpeedValue],@"speed",
                                     cycleStreets.files.clientid,@"clientid",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=CALCULATEROUTE;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
	request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self loadRouteForEndPointsResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
    
    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:@"Obtaining route from CycleStreets.net" andMessage:nil];
	
	
	
}



-(void)loadMetaDataForWaypoint:(WayPointVO*)waypoint{
	
    
  //  NSDictionary *postparameters=@{@"username":[CycleStreets sharedInstance].APIKey,
	//							   @"password":@"cycleStreetsDev"};
	
	NSMutableDictionary *getparameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:waypoint.coordinateString,@"lonlat",
										[CycleStreets sharedInstance].APIKey,@"key",
										nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=WAYPOINTMETADATA;
    request.requestid=ZERO;
    //request.parameters=[@{@"getparameters":getparameters, @"postparameters":postparameters} mutableCopy];
	request.parameters=[getparameters mutableCopy];
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
	__weak __typeof(&*waypoint)weakWaypoint = waypoint;
	request.completionBlock=^(BUNetworkOperation *operation, BOOL complete, NSString *error){
		
		[self loadMetaDataForWaypointResponse:operation forWaypoint:weakWaypoint];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
}


-(void)loadMetaDataForWaypointResponse:(BUNetworkOperation*)response forWaypoint:(WayPointVO*)waypoint{
	
	
	switch(response.responseStatus){
			
        case ValidationRetrieveRouteByIdSuccess:
		{
			NSDictionary *responseDict=response.responseObject;
			
			waypoint.locationname=responseDict[@"features"][0][@"properties"][@"name"];
        }
		break;
			
		default:
			break;
			
			
    }

	
	
}


//
/***********************************************
 * @description			converts array to lat,long|lat,long... formatted string
 ***********************************************/
//
-(NSString*)convertWaypointArrayforRequest:(NSMutableArray*)waypoints{
	
	NSMutableArray *cooordarray=[NSMutableArray array];
	
	for(int i=0;i<waypoints.count;i++){
		
		WayPointVO *waypoint=waypoints[i];
		
		[cooordarray addObject:waypoint.coordinateStringForAPI];
		
	}
	
	return [cooordarray componentsJoinedByString:@"|"];
	
}









#pragma mark - Route Updating for elevation



-(void)updateRoute:(RouteVO*)route{
    
	BetterLog(@"");
    
    NSMutableDictionary *parameters=[NSMutableDictionary dictionaryWithObjectsAndKeys:[CycleStreets sharedInstance].APIKey,@"key",
                                     useDom,@"useDom",
                                     route.plan,@"plan",
                                     route.routeid,@"itinerary",
                                     nil];
    
    BUNetworkOperation *request=[[BUNetworkOperation alloc]init];
    request.dataid=UPDATEROUTE;
    request.requestid=ZERO;
    request.parameters=parameters;
    request.source=DataSourceRequestCacheTypeUseNetwork;
    
    request.completionBlock=^(BUNetworkOperation *operation, BOOL complete,NSString *error){
		
		[self updateRouteResponse:operation];
		
	};
	
	[[BUDataSourceManager sharedInstance] processDataRequest:request];
	
	// format routeid to decimal style ie xx,xxx,xxx
	NSNumberFormatter *currencyformatter=[[NSNumberFormatter alloc]init];
	[currencyformatter setNumberStyle:NSNumberFormatterDecimalStyle];
	NSString *result=[currencyformatter stringFromNumber:[NSNumber numberWithInt:[route.routeid intValue]]];
	
    [[HudManager sharedInstance] showHudWithType:HUDWindowTypeProgress withTitle:[NSString stringWithFormat:@"Updating route %@",result] andMessage:nil];
}


-(void)updateRouteResponse:(BUNetworkOperation*)response{
    
	BetterLog(@"");
    
    switch(response.responseStatus){
            
        case ValidationCalculateRouteSuccess:
        {
           RouteVO *newroute=response.responseObject;
            
			[[SavedRoutesManager sharedInstance] updateRouteWithRoute:newroute];
            
            
            [[HudManager sharedInstance] showHudWithType:HUDWindowTypeSuccess withTitle:nil andMessage:nil];
		}
            break;
            
            
        case ValidationCalculateRouteFailed:
            
            [self queryFailureMessage:@"Unable to find a route with this number."];
            
		break;
			
		default:
			break;
            
            
    }
    
    
}





//
/***********************************************
 * @description			Old Route>New Route conversion evaluation
 ***********************************************/
//

#pragma mark - Legacy Route loading and conversion

-(void)evalRouteArchiveState{
	
	
	// do we have a old route folder
	NSFileManager* fileManager = [NSFileManager defaultManager];
	
	[self createRoutesDir];
	
	
	BOOL isDirectory;
	BOOL doesDirExist=[fileManager fileExistsAtPath:[self oldroutesDirectory] isDirectory:&isDirectory];
	
					   
	if(doesDirExist==YES && isDirectory==YES){
		
		self.legacyRoutes=[NSMutableArray array];
		
		NSError *error=nil;
		NSURL *url = [[NSURL alloc] initFileURLWithPath:[self oldroutesDirectory] isDirectory:YES ];
		NSArray *properties = [NSArray arrayWithObjects: NSURLLocalizedNameKey, nil];
		
		NSArray *oldroutes = [fileManager
						  contentsOfDirectoryAtURL:url
						  includingPropertiesForKeys:properties
						  options:(NSDirectoryEnumerationSkipsPackageDescendants |
								   NSDirectoryEnumerationSkipsHiddenFiles)
						  error:&error];
		
		
		if(error==nil && [oldroutes count]>0){
			
			for(NSURL *filename in oldroutes){
				
				NSData *routedata=[[NSData alloc ] initWithContentsOfURL:filename];
				
				RouteVO *newroute=(RouteVO*)[[ApplicationXMLParser sharedInstance] parseXML:routedata forType:CALCULATEROUTE];
				
				[_legacyRoutes addObject:newroute];
				
				[self saveRoute:newroute];
				
				
			}
			
		}
		
	}else {
		
		BetterLog(@"[INFO] legacy route dir not found, conversion is skipped");
		
	}
	
	self.activeRouteDir=ROUTEARCHIVEPATH;
	
	
}



-(void)legacyRouteCleanup{
	
	self.legacyRoutes=nil;
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSError *error=nil;
	
	[fileManager removeItemAtPath:[self oldroutesDirectory] error:&error];
	
}



- (void) queryFailureMessage:(NSString *)message {
	[[HudManager sharedInstance] showHudWithType:HUDWindowTypeError withTitle:message andMessage:nil];
}



#pragma mark - Route management

- (void) selectRoute:(RouteVO *)route {
	
	BetterLog(@"");
	
	self.selectedRoute=route;
	
	[[SavedRoutesManager sharedInstance] selectRoute:route];
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	[cycleStreets.files setMiscValue:route.fileid forKey:@"selectedroute"];
	
	BetterLog(@"");
	
	[[NSNotificationCenter defaultCenter] postNotificationName:CSROUTESELECTED object:[route routeid]];
	
}


- (void) clearSelectedRoute{
	
	if(_selectedRoute!=nil){
		
		self.selectedRoute=nil;
		
		CycleStreets *cycleStreets = [CycleStreets sharedInstance];
		[cycleStreets.files setMiscValue:EMPTYSTRING forKey:@"selectedroute"];
	}
	
	
}


-(BOOL)hasSelectedRoute{
	return _selectedRoute!=nil;
}


-(BOOL)routeIsSelectedRoute:(RouteVO*)route{
	
	if(_selectedRoute!=nil){
	
		return [route.fileid isEqualToString:_selectedRoute.fileid];
		
	}else{
		return NO;
	}
	
}



- (void)warnOnFirstRoute {
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	NSMutableDictionary *misc = [NSMutableDictionary dictionaryWithDictionary:[cycleStreets.files misc]];
	NSString *experienceLevel = [misc objectForKey:@"experienced"];
	
	if (experienceLevel == nil) {
		[misc setObject:@"1" forKey:@"experienced"];
		[cycleStreets.files setMisc:misc];
		
		UIAlertView *firstAlert = [[UIAlertView alloc] initWithTitle:@"Warning"
													 message:@"Route quality cannot be guaranteed. Please proceed at your own risk. Do not use a mobile while cycling."
													delegate:self
										   cancelButtonTitle:@"OK"
										   otherButtonTitles:nil];
		[firstAlert show];		
	} else if ([experienceLevel isEqualToString:@"1"]) {
		[misc setObject:@"2" forKey:@"experienced"];
		[cycleStreets.files setMisc:misc];
		
		UIAlertView *optionsAlert = [[UIAlertView alloc] initWithTitle:@"Routing modes"
													   message:@"You can change between fastest / quietest / balanced routing type using the route type button above."
													  delegate:self
											 cancelButtonTitle:@"OK"
											 otherButtonTitles:nil];
		[optionsAlert show];
	}	
	 
}





//
/***********************************************
 * @description			Pre Selects route as SR
 ***********************************************/
//
-(void)selectRouteWithIdentifier:(NSString*)identifier{
	
	if (identifier!=nil) {
		RouteVO *route = [_routes objectForKey:identifier];
		if(route!=nil){
			[self selectRoute:route];
		}
	}
	
}

//
/***********************************************
 * @description			loads route from disk and stores
 ***********************************************/
//
-(void)loadRouteWithIdentifier:(NSString*)identifier{
	
	RouteVO *route=nil;
	
	if (identifier!=nil) {
		route = [self loadRouteForFileID:identifier];
	}
	if(route!=nil){
		[_routes setObject:route forKey:identifier];
	}
	
}

//


-(BOOL)hasSavedSelectedRoute{
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	NSString *selectedroutefileid = [cycleStreets.files miscValueForKey:@"selectedroute"];
	
	if(selectedroutefileid!=nil){
		RouteVO *route=[self loadRouteForFileID:selectedroutefileid];
		
		return route!=nil;
		
	}
	return NO;
}


// loads the currently saved selectedRoute by identifier
-(BOOL)loadSavedSelectedRoute{
	
	BetterLog(@"");
	
	CycleStreets *cycleStreets = [CycleStreets sharedInstance];
	NSString *selectedroutefileid = [cycleStreets.files miscValueForKey:@"selectedroute"];
	
	
	if(selectedroutefileid!=nil){
		RouteVO *route=[self loadRouteForFileID:selectedroutefileid];
		
		if(route!=nil){
			[self selectRoute:route];
			return YES;
		}else{
			[[NSNotificationCenter defaultCenter] postNotificationName:CSLASTLOCATIONLOAD object:nil];
			return NO;
		}
		
	}
	
	return NO;
	
}



-(void)removeRoute:(RouteVO*)route{
	
	[_routes removeObjectForKey:route.fileid];
	[self removeRouteFile:route];
	
}



#pragma mark - Route File I/O

-(RouteVO*)loadRouteForFileID:(NSString*)fileid{
	
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", fileid]];
	
	//BetterLog(@"routeFile=%@",routeFile);
	
	NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile:routeFile];
	
	if(data!=nil){
		NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
		RouteVO *route = [unarchiver decodeObjectForKey:kROUTEARCHIVEKEY];
		[unarchiver finishDecoding];
		return route;
	}else{
		BetterLog(@"Unable to load route data for file route_%@",fileid);
	}
	
	return nil;
	
}


- (void)saveRoute:(RouteVO *)route   {
	
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", route.fileid]];
	
	//BetterLog(@"routeFile=%@",routeFile);
	
	NSMutableData *data = [[NSMutableData alloc] init];
	NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	[archiver encodeObject:route forKey:kROUTEARCHIVEKEY];
	[archiver finishEncoding];
	BOOL result=[data writeToFile:routeFile atomically:YES];
	
	BetterLog(@"routesDirectory save: result %i",result);
}


-(void)saveRoutesInBackground:(NSMutableArray*)arr{
	
	__weak __typeof(&*self)weakSelf = self;
	[self bk_performBlockInBackground:^(id obj) {
		
		for(RouteVO *route in arr){
			[weakSelf saveRoute:route];
		}
		
	} afterDelay:0];
	
	
}



- (void)removeRouteFile:(RouteVO*)route{
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", route.fileid]];
	
	BOOL fileexists = [fileManager fileExistsAtPath:routeFile];
	
	if(fileexists==YES){
		
		NSError *error=nil;
		[fileManager removeItemAtPath:routeFile error:&error];
	}
	
}


-(BOOL)createRoutesDir{
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSArray* paths=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString* docsdir=[paths objectAtIndex:0];
	NSString *ipath=[docsdir stringByAppendingPathComponent:ROUTEARCHIVEPATH];
	
	BOOL isDir=YES;
	
	if([fileManager fileExistsAtPath:ipath isDirectory:&isDir]){
		return YES;
	}else {
		
		if([fileManager createDirectoryAtPath:ipath withIntermediateDirectories:NO attributes:nil error:nil ]){
			return YES;
		}else{
			return NO;
		}
	}
}

-(BOOL)removeRoutesDir{
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSArray* paths=NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString* docsdir=[paths objectAtIndex:0];
	NSString *ipath=[docsdir stringByAppendingPathComponent:ROUTEARCHIVEPATH];
	
	BOOL isDir=YES;
	
	if([fileManager fileExistsAtPath:ipath isDirectory:&isDir]){
		NSError *error=nil;
		if([fileManager removeItemAtPath:ipath error:&error ]){
			return YES;
		}else{
			return NO;
		}
	}
	
	return YES;
	
}


#pragma mark - Legacy route methods

// legacy conversion call only
-(RouteVO*)legacyLoadRoute:(NSString*)routeid{
	
	NSString *routeFile = [[self oldroutesDirectory] stringByAppendingPathComponent:routeid];
	
	//BetterLog(@"routeFile=%@",routeFile);
	
	NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile:routeFile];
	NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	RouteVO *route = [unarchiver decodeObjectForKey:kROUTEARCHIVEKEY];
	[unarchiver finishDecoding];
	
	return route;
	
	
}

- (void)legacyRemoveRouteFile:(NSString*)routeid{
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSString *routeFile = [[self routesDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"route_%@", routeid]];
	
	BOOL fileexists = [fileManager fileExistsAtPath:routeFile];
	
	if(fileexists==YES){
		
		NSError *error=nil;
		[fileManager removeItemAtPath:routeFile error:&error];
	}
	
}



#pragma mark - File paths

- (NSString *) oldroutesDirectory {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [[paths objectAtIndex:0] copy];
	return [documentsDirectory stringByAppendingPathComponent:OLDROUTEARCHIVEPATH];
}

- (NSString *) routesDirectory {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [[paths objectAtIndex:0] copy];
	return [documentsDirectory stringByAppendingPathComponent:ROUTEARCHIVEPATH];
}



@end
