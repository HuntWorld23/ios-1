//
//  FavouritesManager.m
//  CycleStreets
//
//  Created by neil on 22/02/2011.
//  Copyright 2011 CycleStreets Ltd. All rights reserved.
//

#import "SavedRoutesManager.h"
#import "CycleStreets.h"
#import "RouteVO.h"
#import "Files.h"
#import "AppDelegate.h"
#import "RouteManager.h"
#import "GlobalUtilities.h"
#import "NSDate+Helper.h"
#import <NSObject+BKBlockExecution.h>
#import "RouteModel.h"

#import "BUPersistentStore.h"
#import "NSFetchedResultsController+Additions.h"
#import "NSManagedObject+BUCoreData.h"
#import "BUPersistentStore+Additions.h"

@interface SavedRoutesManager(Private)

-(void)transferOldFavouritesToRecents;

- (void) saveIndicies;
- (NSMutableDictionary *) loadIndicies;
- (NSString *) indiciesFile;

-(void)purgeOrphanedRoutes:(NSMutableArray*)arr;
-(void)promoteRouteToTopOfDataProvider:(RouteVO*)route;
-(NSString*)findRouteType:(RouteVO*)route;
-(NSUInteger)findIndexOfRouteByID:(NSString*)routeid;

+(NSString*)returnRouteTypeInvert:(NSString*)type;

@end



@implementation SavedRoutesManager
SYNTHESIZE_SINGLETON_FOR_CLASS(SavedRoutesManager);



//=========================================================== 
// - (id)init
//
//=========================================================== 
- (instancetype)init
{
    self = [super init];
    if (self) {
		
        self.routeidStore = [self loadIndicies];
		
		if(_routeidStore==nil){
			self.routeidStore = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[NSMutableArray array], SAVEDROUTE_FAVS,[NSMutableArray array],SAVEDROUTE_RECENTS,nil];
		}
		
		[[BUPersistentStore mainStore] setupWithStoreName:@"CoreDataStore.sqlite" modelName:@"RoutesModel"];
		
		__weak __typeof(&*self)weakSelf = self;
		[self bk_performBlockInBackground:^(id obj) {
			[weakSelf loadSavedRoutes];
		} afterDelay:0];
		
		
    }
    return self;
}


-(void)loadSavedRoutes{
	
	
	NSMutableArray *favarr=[[NSMutableArray alloc]init];
	NSMutableArray *recentarr=[[NSMutableArray alloc]init];
	NSMutableArray *orphanarr=[[NSMutableArray alloc]init];
	
	NSMutableArray *invalidDateArr=[NSMutableArray array];
	
	for(NSString *key in _routeidStore){
		
		NSArray *routes=[_routeidStore objectForKey:key];
		
		for(NSString *routeid in routes){
		
			RouteVO *route=[[RouteManager sharedInstance] loadRouteForFileID:routeid];
			
			// migrate routes that the api has returned invalid dates for
			// RouteManager will re-save these so this should only happen once
			// we pre fix this in the xml parser to stop future occurences while the server fix is done.
			if(route.dateString==nil){
				
				NSDate *newdate=[NSDate dateWithTimeIntervalSince1970:[route.date integerValue]];
				NSString *dateStr=[NSDate stringFromDate:newdate withFormat:[NSDate dbFormatString]];
				if(newdate!=nil){
					route.date=dateStr;
					[invalidDateArr addObject:route];
				}
			}
			
			if(route!=nil){
				if([key isEqualToString:SAVEDROUTE_FAVS]){
					[favarr addObject:route];
				}else{
					[recentarr addObject:route];
				}
			}else{
				[orphanarr addObject:routeid];
			}
		
		}
		
	}
	
	self.favouritesdataProvider=favarr;
	self.recentsdataProvider=recentarr;
	
	// v1>v2 transition method
	[self transferOldFavouritesToRecents];
	
	if(invalidDateArr.count>0)
		[[RouteManager sharedInstance] saveRoutesInBackground:invalidDateArr];
	
	if(orphanarr.count>0)
		[self purgeOrphanedRoutes:orphanarr];
	
}


#pragma mark - Legacy migration methods


//
/***********************************************
 * @description			v3 > CoreData migration
 ***********************************************/
//

// this should be user initiated or specifically stall app to complete
// ie dont do this in the background

-(void)migrateFileRoutesToCoreData{
	
	int recentCount=0;
	
	for(NSString *key in _routeidStore){
		
		NSArray *routes=[_routeidStore objectForKey:key];
		recentCount=routes.count;
		
		for(NSString *routeid in routes){
			
			RouteVO *route=[[RouteManager sharedInstance] loadRouteForFileID:routeid];
			
			if(route.dateString==nil){
				
				NSDate *newdate=[NSDate dateWithTimeIntervalSince1970:[route.date integerValue]];
				NSString *dateStr=[NSDate stringFromDate:newdate withFormat:[NSDate dbFormatString]];
				if(newdate!=nil){
					route.date=dateStr;
				}
			}
			
			RouteModel *newRoute=[RouteModel create];
			[newRoute populateWithLegacyObject:route];
			
			if(route!=nil){
				if([key isEqualToString:SAVEDROUTE_FAVS]){
					newRoute.storeTypeValue=CSRouteSaveTypeFavourite;
				}else{
					newRoute.storeTypeValue=CSRouteSaveTypeRecent;
				}
			}
		}
		
		[[BUPersistentStore mainStore] fastSave];
		
		
		
	}
	
	
	// do test load of data
	NSError *error=nil;
	NSFetchRequest *recentRequest=[self fetchRequestFor:CSRouteSaveTypeRecent];
	NSArray *results=[[BUPersistentStore mainStore] allForFetchRequest:recentRequest error:&error];
	
	
	if(error==nil && results.count==recentCount){
		
		BOOL removedDir=[[RouteManager sharedInstance] removeRoutesDir];
		
		if(removedDir==YES){
			
			NSFileManager* fileManager = [NSFileManager defaultManager];
			
			if([fileManager fileExistsAtPath:[self indiciesFile]]){
				NSError *error=nil;
				if([fileManager removeItemAtPath:[self indiciesFile] error:&error ]){
					BetterLog(@"removed legacy indicies file");
				}else{
					BetterLog(@"didnt remove indicies file");
				}
			}
			
		}else{
			BetterLog(@"Unable to remove legacy routes dir");
		}
		
	}
	
	
	// removed legacy data
	

	
	
	
	// re try using fetchedresults controllers
	
}


- (NSFetchRequest *)fetchRequestFor:(CSRouteSaveType)saveType {
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	NSManagedObjectContext *context=[[BUPersistentStore mainStore] managedObjectContext];
	[fetchRequest setEntity:[RouteModel entityInManagedObjectContext:context]];
	[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"storeType = %@",[AppConstants routeSaveConstantToString:saveType]]];
	[fetchRequest setFetchBatchSize:100];
	
	NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"date" ascending:NO];
	NSArray *sortDescriptors = @[sortDescriptor];
	[fetchRequest setSortDescriptors:sortDescriptors];
	
	
	return fetchRequest;
	
}




//
/***********************************************
 * @description			v1 > v2 migration
 ***********************************************/
//
-(void)transferOldFavouritesToRecents{
	
	BetterLog(@"");
	
	NSMutableArray *legacyRoutes=[RouteManager sharedInstance].legacyRoutes;
	
	NSMutableArray *routeidarr=[_routeidStore objectForKey:SAVEDROUTE_RECENTS];
	
	if(legacyRoutes!=nil){
		
		BetterLog(@"transferring legacy routes");
		
		for(RouteVO *route in legacyRoutes){
			
			[_recentsdataProvider addObject:route];
			[routeidarr addObject:route.fileid];
			
		}
		
		[(Files*)[CycleStreets sharedInstance].files removeDataFileForType:@"favourites"];
		
		[self saveIndicies];
		
		[[RouteManager sharedInstance] legacyRouteCleanup];
		
	}
	
}




-(NSMutableArray*)dataProviderForType:(NSString*)type{
    
    if([type isEqualToString:SAVEDROUTE_FAVS]){
		return _favouritesdataProvider;
	}else{
		return _recentsdataProvider;
	}
}


//
/***********************************************
 * @description			adda new route to the temp stores and update the saved index file
 ***********************************************/
//
-(void)addRoute:(RouteVO*)route toDataProvider:(NSString*)type{
	
	NSMutableArray *arr=[_routeidStore objectForKey:type];
	
	if([arr indexOfObject:route.fileid]==NSNotFound){
		
		if([type isEqualToString:SAVEDROUTE_FAVS]){
			[_favouritesdataProvider insertObject:route atIndex:0];
		}else{
			BetterLog(@"_recentsdataProvider count pre add: %lu",(unsigned long)_recentsdataProvider.count);
			[_recentsdataProvider insertObject:route atIndex:0];
			BetterLog(@"_recentsdataProvider count post add: %lu",(unsigned long)_recentsdataProvider.count);
		}
		
		
		[arr addObject:route.fileid];
		
		[self saveIndicies];
		
		
	}else{
		
		
		BetterLog(@"[ERROR] This route filed is already in the idStore: %@",route.fileid);
		
		
	}
	
	
	
	
}

//
/***********************************************
 * @description			handles Route movement from Recents <> favourites
 ***********************************************/
//
-(BOOL)moveRoute:(RouteVO*)route toDataProvider:(NSString*)type{
	
    NSString *key=[self findRouteType:route];
    
    if([key isEqualToString:@"NotFound"]){
        BetterLog(@"[ERROR] Unable to find current route in dataProvider");
		return NO;
    }else{
        
        NSMutableArray *fromArr;
        if([type isEqualToString:SAVEDROUTE_RECENTS]){
            fromArr=_favouritesdataProvider;
        }else{
            fromArr=_recentsdataProvider;
        }
        
        NSUInteger index=[fromArr indexOfObjectIdenticalTo:route];
		if(index<[fromArr count])
			[fromArr removeObjectAtIndex:index];
        
        if([type isEqualToString:SAVEDROUTE_FAVS]){
            [_favouritesdataProvider insertObject:route atIndex:0];
        }else{
            [_recentsdataProvider insertObject:route atIndex:0];
        }
		
		// update id arrs
		NSMutableArray *newidarr=[_routeidStore objectForKey:type];
		NSMutableArray *idarr=[_routeidStore objectForKey:[SavedRoutesManager returnRouteTypeInvert:type]];
		[newidarr addObject:route.fileid];
		[idarr removeObject:route.fileid];
		
		[self saveIndicies];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:SAVEDROUTEUPDATE object:nil];
		
		return YES;
    }
	
	
}


-(void)removeRoute:(RouteVO*)route fromDataProvider:(NSString*)type{
    
    NSMutableArray *arr;
    if([type isEqualToString:SAVEDROUTE_FAVS]){
        arr=_favouritesdataProvider;
    }else{
        arr=_recentsdataProvider;
    }
    
    NSUInteger index=[arr indexOfObjectIdenticalTo:route];
	
	if(index<[arr count]){
		
		[arr removeObjectAtIndex:index];
	
		NSMutableArray *idarr=[_routeidStore objectForKey:type];
		[idarr removeObject:route.fileid];
	
		[self saveIndicies];
	}
    
}

-(void)removeRoute:(RouteVO*)route{
	
	for(NSString *key in _routeidStore){
		
		NSMutableArray *routes=[_routeidStore objectForKey:key];
		
		NSUInteger index=[routes indexOfObjectIdenticalTo:route];
		
		if(index!=-1 && index!=0){
			[routes removeObjectAtIndex:index];
			[[RouteManager sharedInstance] removeRoute:route];
		}
		
	}
	
	
}


// called as result of RouteManager select Route
- (void) selectRoute:(RouteVO *)route {
	
    // TODO: this should only occur if its in the Fav array
   
    // OR have separate button in UI that shows the RouteSummary with the selected route
    // always, then no need for this odd re-organising
	//[self promoteRouteToTopOfDataProvider:route];
	
}


//
/***********************************************
 * @description			Persists a route to disk and updates the UI
 ***********************************************/
//
-(void)saveRouteChangesForRoute:(RouteVO*)route{
	
	[[RouteManager sharedInstance] saveRoute:route];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:SAVEDROUTEUPDATE object:route];
	
}



//
/***********************************************
 * @description			Finds and replaces a route with same fileid
 ***********************************************/
//
-(void)updateRouteWithRoute:(RouteVO*)route{
	
	NSString *type=[self findRouteType:route];
	NSUInteger index=[self findIndexOfRoute:route];
	
	if(index!=NSNotFound){
		if([type isEqualToString:SAVEDROUTE_FAVS]){
			[_favouritesdataProvider replaceObjectsAtIndexes:[NSIndexSet indexSetWithIndex:index] withObjects:@[route]];
		}else{
			[_recentsdataProvider replaceObjectsAtIndexes:[NSIndexSet indexSetWithIndex:index] withObjects:@[route]];
		}
		[self saveRouteChangesForRoute:route];
	}else{
		BetterLog(@"[ERROR] Unable to find route to update");
	}
	
}


//
/***********************************************
 * @description			Utility
 ***********************************************/
//

// locates a route and move it to top of its dp, occurs when a route is selected by user
-(void)promoteRouteToTopOfDataProvider:(RouteVO*)route{
	
	for(NSString *key in _routeidStore){
		
		NSMutableArray *routes=[_routeidStore objectForKey:key];
		
		NSUInteger index=[routes indexOfObject:route.fileid];
		
		if(index!=NSNotFound && index!=0){
			[routes exchangeObjectAtIndex:0 withObjectAtIndex:index];
		}
		
	}
	
}


-(NSString*)findRouteType:(RouteVO*)route{
	
	for(NSString *key in _routeidStore){
		
		NSMutableArray *routes=[_routeidStore objectForKey:key];
		
		NSUInteger index=[routes indexOfObject:route.fileid];
		
		if(index!=NSNotFound){
			return key;
		}
		
	}
	
	return @"NotFound";
	
}


-(NSUInteger)findIndexOfRouteByID:(NSString*)routeid{ // will be route.fileid format
	
	NSUInteger index=NSNotFound;
	
	for(NSString *key in _routeidStore){
		
		NSMutableArray *routes=[_routeidStore objectForKey:key];
		
		NSUInteger index=[routes indexOfObject:routeid];
		
		if(index!=NSNotFound){
			break;
		}
		
	}
	
	return index;
}


//
/***********************************************
 * @description			Find the index of an exisitng route with the same fileid
 ***********************************************/
//
-(NSUInteger)findIndexOfRoute:(RouteVO*)findroute{
	
	NSUInteger index=NSNotFound;
	
	index=[_recentsdataProvider indexOfObjectPassingTest:
		   ^(RouteVO *obj, NSUInteger idx, BOOL *stop) {
			   BOOL res;
			   
			   if ([findroute.fileid isEqualToString:obj.fileid]) {
				   res = YES;
				   *stop = YES;
			   } else {
				   res = NO;
			   }
			   return res;
		   }];
	
	if(index==NSNotFound){
		
		index=[_favouritesdataProvider indexOfObjectPassingTest:
			   ^(RouteVO *obj, NSUInteger idx, BOOL *stop) {
				   BOOL res;
				   
				   if ([findroute.fileid isEqualToString:obj.fileid]) {
					   res = YES;
					   *stop = YES;
				   } else {
					   res = NO;
				   }
				   return res;
			   }];
		
	}
	
	
	return index;
}


-(BOOL)findRouteWithId:(NSString*)routeid andPlan:(NSString*)plan{
	
	NSString *fileid=[NSString stringWithFormat:@"%@_%@",routeid,plan];
	BOOL found=NO;
	
	for(NSString *key in _routeidStore){
		
		NSMutableArray *routes=[_routeidStore objectForKey:key];
		
		NSUInteger index=[routes indexOfObject:fileid];
		
		if(index!=NSNotFound){
			found=YES;
			break;
		}
		
	}
	
	return found;
	
}


//
/***********************************************
 * @description			File I/O
 ***********************************************/
//

- (NSMutableDictionary *) loadIndicies {
	
	NSMutableDictionary *result=[NSMutableDictionary dictionaryWithContentsOfFile:[self indiciesFile]];
	BetterLog(@"loadIndicies count=%lu",(unsigned long)result.count);
	
	return result;	
}

- (void) saveIndicies {
	
	BOOL result=[_routeidStore writeToFile:[self indiciesFile] atomically:YES];
	BetterLog(@"saveIndicies result: %i",result);
}


-(void)purgeOrphanedRoutes:(NSMutableArray*)arr{
	
	BetterLog(@"");
	
	for (NSString *routeid in arr){
		[[RouteManager sharedInstance] legacyRemoveRouteFile:routeid];
	}
	
}

+(NSString*)returnRouteTypeInvert:(NSString*)type{
	if ([type isEqualToString:SAVEDROUTE_FAVS]) {
		return SAVEDROUTE_RECENTS;
	}
	return SAVEDROUTE_FAVS;
}


- (NSString *) indiciesFile {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [[paths objectAtIndex:0] copy];
	return [documentsDirectory stringByAppendingPathComponent:SAVEDROUTESARCHIVEPATH];
}

@end
