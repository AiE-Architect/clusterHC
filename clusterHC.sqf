/*
* clusterHC.sqf
*
* In the mission editor, name the Headless Clients "HC", "HC2", "HC3" without the quotes
*
* In the mission init.sqf, spawn clusterHC.sqf with:
* [] spawn compile preprocessFileLineNumbers "clusterHC.sqf"
*
* It seems that the dedicated server and headless client processes never use more than 20-22% CPU each.
* With a dedicated server and 3 headless clients, that's about 88% CPU with 10-12% left over.  Far more efficient use of your processing power.
* 
* _isLOS function provided by SaOK - http://forums.bistudio.com/showthread.php?135252-Line-Of-Sight-(Example-Thread)&highlight=los
*
*/

// These variables may be manipulated
rebalanceTimer = 5;  // Rebalance sleep timer in seconds
cleanUpThreshold = 5; // Threshold of number of dead bodies + destroyed vehicles before forcing a clean up
fpsLowerBound = 25;
fpsUpperThreshold = 35;

_hintDebug = compile '
  _tmp = 0;
  { if (!simulationEnabled _x) then {_tmp = _tmp + 1;}; } forEach (allUnits);
  hintSilent composeText [format ["FPS: %1", diag_fps], lineBreak,
              format ["FPSMin: %1", diag_fpsmin], lineBreak,
              format ["Number of Units: %1", count allUnits], lineBreak,
              format ["BLUFOR: %1", west countSide allUnits], lineBreak,
              format ["OPFOR: %1", east countSide allUnits], lineBreak,
              format ["CIV: %1", civilian countSide allUnits], lineBreak,
              format ["Cached: %1", _tmp]];
';

_enableAllSim = compile '
  while {true} do {
    waitUntil {diag_fps >= fpsUpperThreshold};
    {
      if (diag_fps > fpsLowerBound) then {{_x enableSimulation true; _x hideObject false;} forEach (units _x);};      
    } forEach (allGroups);
  };
';

/*
_a = _unit;  
_b = _near;  
_eyedv = eyedirection _a;  
_eyed = ((_eyedv select 0) atan2 (_eyedv select 1));   
_dirto = ([_b, _a] call bis_fnc_dirto);  
_ang = abs (_dirto - _eyed); 
_eyepa = eyepos _a; 
_eyepb = eyepos _b; 
_tint = terrainintersectasl [_eyepa, _eyepb]; 
_lint = lineintersects [_eyepa, _eyepb]; 
if (((_ang > 120) && (_ang < 240)) && {!(_lint) && !(_tint)}) then
*/

_cacheCheckPlayer = '
  _getGroupDistances = compile "
    _groupDistancesInside = [ ["""",0] ];

    {
      _groupDistancesInside = _groupDistancesInside + [ [groupID _x, (getPosASL player) distance (getPosASL ((units _x) select 0))] ];
    } forEach (allGroups);
  _groupDistancesInside";

  _getFurthestElement = compile "
    _groupDistancesInside = _this;
    _furthestElementInside = 0;
    _currentDistance = 0;
    _numGroupDistances = count _groupDistancesInside;
    for ""_i"" from 0 to (_numGroupDistances - 1) step 1 do {
      _currentDistance = ((_groupDistancesInside select _i) select 1);
      if (isNil ""_currentDistance"") then { _currentDistance = 0; };
      
      if ( _currentDistance != 0 ) then {
        if ( ((_groupDistancesInside select _i) select 1) > ((_groupDistancesInside select _furthestElementInside) select 1) ) then { _furthestElementInside = _i; };
      };
    };
  _furthestElementInside";

  _isLOS = compile "      
    _a = _this select 0;
    _b = _this select 1;
    _eyeDV = eyeDirection _b;
    _eyeD = ((_eyeDV select 0) atan2 (_eyeDV select 1));
    _dirTo = [_b, _a] call BIS_fnc_dirTo;
    _ang = abs (_dirto - _eyed);
    _eyePb = eyePos _b;
    _eyePa = eyePos _a;
    _tint = terrainintersectasl [_eyePa, _eyePb];
    _lint = lineintersects [_eyePa, _eyePb];
    _rc = false;

    if (((_ang > 120) && (_ang < 240)) && {!(_lint) && !(_tint)}) then { _rc = true; };
  _rc";

  while {true} do {
    waitUntil {diag_fps <= fpsLowerBound};
    diag_log "clusterHC: Cache Start";

    _groupDistances = call _getGroupDistances;
    waitUntil {!isNil "_groupDistances"};

    while {diag_fps <= fpsLowerBound} do {
      _cacheCount = 0;
      { if (_x select 1 == 0) then { _cacheCount = _cacheCount + 1; }; } forEach (_groupDistances);
      if ( _cacheCount == ((count _groupDistances) - 1) ) then { diag_log "clusterHC: Recall _getGroupDistances"; _groupDistances = call _getGroupDistances; };

      _furthestElement = _groupDistances call _getFurthestElement;
      waitUntil {!isNil "_furthestElement"};

      if ( ((_groupDistances select _furthestElement) select 1) != 0 ) then {
        diag_log format["clusterHC: Furthest group is %1", str(_groupDistances select _furthestElement)];

        { // forEach (allGroups)
          if (groupID _x == (_groupDistances select _furthestElement) select 0) then {
              {
                if (!isPlayer _x) then {
                  _losBlocked = (!([_x, player] call _isLOS));
                  waitUntil {!isNil "_losBlocked"};

                  if (_losBlocked) then {
                    diag_log format ["clusterHC: Caching unit %1", _x];
                    _x enableSimulation false;
                    _x hideObject false;
                  } else {
                    diag_log format ["clusterHC: _losBlocked = %1 :: Player can see unit %2", str(_losBlocked), _x];
                  };
              } forEach (units _x); };              
            
            _groupDistances set [_furthestElement, ["", 0]];
          };
        } forEach (allGroups);
      };
    };
    diag_log "clusterHC: Cache Complete";
  };
';

diag_log "clusterHC: Started";

// Player clients
if (!isServer && hasInterface) exitWith {
  waitUntil {!isNull player};
  ["", "onEachFrame", _hintDebug] call BIS_fnc_addStackedEventHandler;
  [] spawn _enableAllSim;
  [] spawn _cacheCheckPlayer;
};

waitUntil {!isNil "HC"};
waitUntil {!isNull HC};

// Leave these variables as-is, we'll auto set them later
_HC_ID = -1; // Will become the Client ID of HC
_HC2_ID = -1; // Will become the Client ID of HC2
_HC3_ID = -1; // Will become the Client ID of HC3
HCSimArray = []; // Will become an array of groups HC owns. Server broadcasts this to HC for simulations
HC2SimArray = []; // Will become an array of groups HC2 owns. Server broadcasts this to HC2 for simulations
HC3SimArray = []; // Will become an array of groups HC3 owns. Server broadcasts this to HC3 for simulations

// Function _cacheCheckHC
// Input: HCSimArray, HC2SimArray, or HC3SimArray
// Example: HCSimArray call _cacheCheckHC;
_cacheCheckHC = compile '
  _thisSimArray = _this;

  { _x enableSimulation true; _x hideObject false; } forEach (allUnits);

  while {diag_fps <= fpsLowerBound} do {
    _groupDistances = [ ["", ["",0]] ];

    _numThisSimArray = count _thisSimArray;
    for "_i" from 0 to (_numThisSimArray - 1) step 1 do {
      _furthestElement = 0;

      { _groupDistances = _groupDistances + [ [format["%1", _i], [groupID _x, (getPosASL ((_thisSimArray select _i) select 0)) distance (getPosASL (_x select 0))]] ]; } forEach (allGroups);

      diag_log format["clusterHC: _groupDistances = %1", str(_groupDistances)];
      diag_log "clusterHC: Finding _furthestElement";
      
      _numGroupDistances = count _groupDistances;
      for "_j" from 0 to (_numGroupDistances - 1) step 1 do {
        if ( ( ((_groupDistances select _j) select 1) select 1 ) != 0 ) then {
          if ( (((_groupDistances select _j) select 1) select 1) > (((_groupDistances select _furthestElement) select 1) select 1) ) then { _furthestElement = _j; };
        };
      };

      diag_log format["clusterHC: _furthestElement = %1", str(_groupDistances select _furthestElement)];

      if ( (((_groupDistances select _furthestElement) select 1) select 1) != 0 ) then {
        diag_log format["clusterHC: Furthest group from %1 is %2", str(_thisSimArray select _i), str((_groupDistances select _furthestElement) select 1))];

        { // forEach (allGroups)
          if (groupID _x == ( ((_groupDistances select _furthestElement) select 1) select 0) ) exitWith {
            { _x enableSimulation false; _x hideObject false;} forEach (units _x);
            _groupDistances set [_furthestElement, [format["%1", _i], ["", 0]]];

            if (simulationEnabled ((units _x) select 0)) then { diag_log format["clusterHC: Group (%1) cached", groupID _x]; };          
          };
        } forEach (allGroups);
    };
  };

  { { _x enableSimulation true; _x hideObject false; } forEach (units _x); } forEach (_thisSimArray);
  true;';

diag_log format["clusterHC: First pass will begin in %1 seconds", rebalanceTimer];

// Only HCs should run this infinite loop to re-enable simulations for AI that it owns
if (!isServer && !hasInterface) exitWith {
  while {true} do {
    sleep rebalanceTimer;

    _numSimulating = 0;

    // Delegate AI simulations
    _rc = false;

    switch (profileName) do {
        case "HC": {
          diag_log "clusterHC: Starting _cacheCheckHC";
          HCSimArray call _cacheCheckHC;
          diag_log "clusterHC: Finished _cacheCheckHC";

          { if (simulationEnabled _x) then { _numSimulating = _numSimulating + 1; }; } forEach (allUnits);
        };
        case "HC2": {
          diag_log "clusterHC: Starting _cacheCheckHC";
          HC2SimArray call _cacheCheckHC;          
          diag_log "clusterHC: Finished _cacheCheckHC";

          { if (simulationEnabled _x) then { _numSimulating = _numSimulating + 1; }; } forEach (allUnits);
        };
        case "HC3": {
          diag_log "clusterHC: Starting _cacheCheckHC";
          HC3SimArray call _cacheCheckHC;          
          diag_log "clusterHC: Finished _cacheCheckHC";

          { if (simulationEnabled _x) then { _numSimulating = _numSimulating + 1; }; } forEach (allUnits);
        };
        default {diag_log "clusterHC: [ERROR] HC Profile Name Not Recognized"; };
    };

    diag_log format ["clusterHC: [INFO] [%1] Currently simulating %2 entities on this HC", profileName, _numSimulating];
  };
};

// Only the server should get to this part

// Function _cleanUp
// Example: [] spawn _cleanUp;
_cleanUp = compile '
  // Force clean up dead bodies and destroyed vehicles
  if (count allDead > cleanUpThreshold) then {
    _numDeleted = 0;
    {
      deleteVehicle _x;

      _numDeleted = _numDeleted + 1;
    } forEach (allDead);

    diag_log format ["clusterHC: Cleaned up %1 dead bodies/destroyed vehicles", _numDeleted];
  };';

while {true} do {
  // Rebalance every rebalanceTimer seconds to avoid hammering the server
  sleep rebalanceTimer;

  // Spawn _cleanUp function in a seperate thread
  [] spawn _cleanUp;

  _numSimulating = 0;

  { if (simulationEnabled _x) then { _numSimulating = _numSimulating + 1; }; } forEach (allUnits);
  if (_numSimulating > 0) then { diag_log format ["clusterHC: [INFO] [Server] Currently simulating %1 entities", _numSimulating]; };
  
  { if (!isPlayer _x) then { _x enableSimulation false; _x hideObject false;}; } forEach (allUnits);

  // Do not enable load balancing unless more than one HC is present
  // Leave this variable false, we'll enable it automatically under the right conditions  
  _loadBalance = false;

   // Get HC Client ID else set variables to null
   try {
    _HC_ID = owner HC;

    if (_HC_ID > 2) then {
      diag_log format ["clusterHC: Found HC with Client ID %1", _HC_ID];
    } else { 
      diag_log "clusterHC: [WARN] HC disconnected";

      HC = objNull;
      _HC_ID = -1;
    };
  } catch { diag_log format ["clusterHC: [ERROR] [HC] %1", _exception]; HC = objNull; _HC_ID = -1; };

  // Get HC2 Client ID else set variables to null
  if (!isNil "HC2") then {
    try {
      _HC2_ID = owner HC2;

      if (_HC2_ID > 2) then {
        diag_log format ["clusterHC: Found HC2 with Client ID %1", _HC2_ID];
      } else { 
        diag_log "clusterHC: [WARN] HC2 disconnected";
        
        HC2 = objNull;
        _HC2_ID = -1;
      };
    } catch { diag_log format ["clusterHC: [ERROR] [HC2] %1", _exception]; HC2 = objNull; _HC2_ID = -1; };
  };

  // Get HC3 Client ID else set variables to null
  if (!isNil "HC3") then {
    try {
      _HC3_ID = owner HC3;

      if (_HC3_ID > 2) then {
        diag_log format ["clusterHC: Found HC3 with Client ID %1", _HC3_ID];
      } else { 
        diag_log "clusterHC: [WARN] HC3 disconnected";
        
        HC3 = objNull;
        _HC3_ID = -1;
      };
    } catch { diag_log format ["clusterHC: [ERROR] [HC3] %1", _exception]; HC3 = objNull; _HC3_ID = -1; };
  };

  // If no HCs present, wait for HC to rejoin
  if ( (isNull HC) && (isNull HC2) && (isNull HC3) ) then { waitUntil {!isNull HC}; };  
  
  // Check to auto enable Round-Robin load balancing strategy
  if ( (!isNull HC && !isNull HC2) || (!isNull HC && !isNull HC3) || (!isNull HC2 && !isNull HC3) ) then { _loadBalance = true; };
  
  if ( _loadBalance ) then {
    diag_log "clusterHC: Starting load-balanced transfer of AI groups to HCs";    
  } else {
    // No load balancing
    diag_log "clusterHC: Starting transfer of AI groups to HC";
  };

  // Determine first HC to start with
  _currentHC = 0;

  if (!isNull HC) then { _currentHC = 1; } else { 
    if (!isNull HC2) then { _currentHC = 2; } else { _currentHC = 3; };
  };  

  // Pass the AI
  _numTransfered = 0;
  {
    _swap = true;

    // If a player is in this group, don't swap to an HC
    { if (isPlayer _x) then { _swap = false; }; } forEach (units _x);

    // Enable simulations for the duration of the AI pass
    { _x enableSimulation true; _x hideObject false; } forEach (units _x);

    // If load balance enabled, round robin between the HCs - else pass all to HC
    if ( _swap ) then {
      _rc = false;

      if ( _loadBalance ) then {
        switch (_currentHC) do {
          case 1: { _rc = _x setGroupOwner _HC_ID; if (!isNull HC2) then { _currentHC = 2; } else { _currentHC = 3; }; };
          case 2: { _rc = _x setGroupOwner _HC2_ID; if (!isNull HC3) then { _currentHC = 3; } else { _currentHC = 1; }; };
          case 3: { _rc = _x setGroupOwner _HC3_ID; if (!isNull HC) then { _currentHC = 1; } else { _currentHC = 2; }; };
          default { diag_log format["clusterHC: [ERROR] No Valid HC to pass to.  _currentHC = %1", _currentHC]; };
        };
      } else {
        switch (_currentHC) do {
          case 1: { _rc = _x setGroupOwner _HC_ID; };
          case 2: { _rc = _x setGroupOwner _HC2_ID; };
          case 3: { _rc = _x setGroupOwner _HC3_ID; };
          default { diag_log format["clusterHC: [ERROR] No Valid HC to pass to.  _currentHC = %1", _currentHC]; };
        };
      };

      // Disable simulations for this group after the pass
      { if (!isPlayer _x) then { _x enableSimulation false; _x hideObject false;}; } forEach (units _x);

      // If the transfer was successful, count it for accounting and diagnostic information
      if ( _rc ) then { _numTransfered = _numTransfered + 1; };
    };
  } forEach (allGroups);

  // Divide up AI to delegate to HC(s)
  _numHC = 0;
  _numHC2 = 0;
  _numHC3 = 0;
  _HCSim = [];
  _HC2Sim = [];
  _HC3Sim = [];

  {
    switch (owner ((units _x) select 0)) do {
      case _HC_ID: { _HCSim = _HCSim + [_x]; _numHC = _numHC + 1; };
      case _HC2_ID: { _HC2Sim = _HC2Sim + [_x]; _numHC2 = _numHC2 + 1; };
      case _HC3_ID: { _HC3Sim = _HC3Sim + [_x]; _numHC3 = _numHC3+ 1; };
      case 1;
      case 2: { { _x enableSimulation true; _x hideObject false; } forEach (units _x); };
    };
  } forEach (allGroups);

  HCSimArray = _HCSim; _HC_ID publicVariableClient "HCSimArray";
  HC2SimArray = _HC2Sim; _HC2_ID publicVariableClient "HC2SimArray";
  HC3SimArray = _HC3Sim; _HC3_ID publicVariableClient "HC3SimArray";

  if (_numTransfered > 0) then {
    // More accounting/diagnostic information
    diag_log format ["clusterHC: Transfered %1 AI groups to HC(s)", _numTransfered];

    if (_numHC > 0) then { diag_log format ["clusterHC: %1 AI groups currently on HC", _numHC]; };
    if (_numHC2 > 0) then { diag_log format ["clusterHC: %1 AI groups currently on HC2", _numHC2]; };
    if (_numHC3 > 0) then { diag_log format ["clusterHC: %1 AI groups currently on HC3", _numHC3]; };
  } else {
    diag_log "clusterHC: No rebalance or transfers required this round";
  };

  diag_log format ["clusterHC: %1 AI groups total across all HC(s)", (_numHC + _numHC2 + _numHC3)];  
};