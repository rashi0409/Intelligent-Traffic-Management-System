function traffic_gui_psoc_full
    % Create figure (resizable & maximized)
    fig = figure('Position',[100 100 1000 600],...
                 'Color','white','MenuBar','none',...
                 'Name','Traffic Signal GUI (PSoC Controlled)',...
                 'NumberTitle','off','Resize','on',...
                 'WindowState','maximized',...
                 'CloseRequestFcn',@onClose);
    axis off;

    % ==== Road Layout ====
    ax = axes('Parent',fig,'Position',[0 0 1 1]); hold on;
    fill([-0.05 1.05 1.05 -0.05],[0.4 0.4 0.6 0.6],[.85 .85 .85],'EdgeColor','none');
    fill([0.45 0.55 0.55 0.45],[-0.05 -0.05 1.05 1.05],[.85 .85 .85],'EdgeColor','none');
    axis([0 1 0 1]); axis off;
    text(0.48,0.52,'Traffic Signal','FontSize',14,'FontWeight','bold','Parent',ax);

    % ==== Input Fields (Car Counts) ====
    labels = {'A→B Cars:','B→A Cars:','C→D Cars:','D→C Cars:'};
    positions = [500 350;950 350;700 200;700 520];
    h.edits = gobjects(1,4);
    for i = 1:4
        uicontrol(fig,'Style','text','String',labels{i},...
                  'Position',[positions(i,1),positions(i,2)+25,80,20],...
                  'BackgroundColor','white','FontSize',10);
        h.edits(i) = uicontrol(fig,'Style','edit','String','0',...
                  'Position',[positions(i,1)+80,positions(i,2)+25,40,20]);
    end

    % ==== Signal Lights ====
    lightPos = [0.42 0.495; 0.58 0.495; 0.495 0.38;0.495 0.65 ];
    h.lights = struct('r',[],'y',[],'g',[]);
    for i = 1:4
        x = lightPos(i,1); y = lightPos(i,2);
        % Create the red, yellow and green light rectangles
        h.lights(i).r = rectangle(ax,'Position',[x y 0.01 0.02],...
                          'Curvature',[1 1],'FaceColor','red','EdgeColor','none');
        h.lights(i).y = rectangle(ax,'Position',[x y-0.025 0.01 0.02],...
                          'Curvature',[1 1],'FaceColor',[0.3 0.3 0],'EdgeColor','none');
        h.lights(i).g = rectangle(ax,'Position',[x y-0.05 0.01 0.02],...
                          'Curvature',[1 1],'FaceColor',[0 0.3 0],'EdgeColor','none');
    end

    % ==== Info Displays ====
    % timerText will show the countdown (3s, 2s, 1s)
    h.timerText = uicontrol(fig,'Style','text','String','Time Left: --',...
                  'Position',[300 180 160 20],'BackgroundColor','white','FontSize',12);
    % stateText now displays Speed information ("Speed: 5 cars/3s")
    h.stateText = uicontrol(fig,'Style','text','String','Speed: --',...
                  'Position',[300 160 160 20],'BackgroundColor','white','FontSize',12);

    % ==== Buttons ====
    uicontrol(fig,'Style','pushbutton','String','Start',...
              'Position',[450 50 100 30],...
              'Callback',@(src,evt) onStart(h,fig));
    uicontrol(fig,'Style','pushbutton','String','Stop',...
              'Position',[580 50 100 30],...
              'Callback',@(src,evt) onStop());

    % Store h in guidata for access in callbacks
    guidata(fig,h);
end

%% --- Callback: Start
function onStart(h,fig)
    % Prevent multiple starts by checking if serial object already exists
    if isfield(h,'serialObj') && isvalid(h.serialObj)
        return;
    end

    % Open serial port COM11 with 9600 baud
    try
        s = serialport('COM12',9600);
        configureTerminator(s,"LF"); flush(s);
    catch
        errordlg('Cannot open COM11','Serial Error'); return;
    end
    h.serialObj = s;
    guidata(fig,h);

    % Send car counts to the PSoC
    sendCarCounts(s,h);

    % Set up a timer to periodically (every 0.2s) read serial data from the PSoC
    t = timer('ExecutionMode','fixedRate','Period',0.2,...
              'TimerFcn',@(~,~) serialReadUpdate(h,fig));
    h.timerObj = t;
    guidata(fig,h);
    start(t);
end

%% --- Send Car Counts
function sendCarCounts(s,h)
    % Define the directions (for sending counts)
    dirs = ["A2B","B2A","C2D","D2C"];
    for i = 1:4
        c = str2double(get(h.edits(i),'String'));
        if isnan(c) || c < 0, c = 0; end
        writeline(s, sprintf('%s,%d', dirs(i), c));
        pause(0.1);
    end
    writeline(s, 'END');  % signal the end of the count transmission
end

%% --- TimerFcn: Read Serial & Process Update
function serialReadUpdate(h,fig)
    s = h.serialObj;
    while s.NumBytesAvailable > 0
        line = readline(s);
        disp("Received: " + line);

        % Expecting a message in the format:
        % "GreenPath:<path>,<speed>,<greenTime>s,<updatedCount>"
        if startsWith(line, "GreenPath:")
            parts = strsplit(strtrim(line), ',');
            % Extract active path (numeric; 1-indexed)
            activePath = str2double(extractAfter(parts{1},"GreenPath:"));
            % Field 2: speed value (as a string or numeric value)
            speedVal = parts{2};  
            % Field 3: Green time in seconds (e.g., "3s")
            greenTime = sscanf(parts{3}, '%ds');
            % Field 4: Updated car count for that path
            updatedCount = str2double(parts{4});

            % Process the green cycle and then execute the yellow transition
            processGreenPathMessage(h, activePath, speedVal, greenTime, updatedCount);
            
        elseif startsWith(line,"Count:")
            % This branch may still update counts based on messages like "Count:A2B,5"
            parts = strsplit(strtrim(line),':,');
            name = parts{2};
            val  = str2double(parts{3});
            idx = find(["A2B","B2A","C2D","D2C"] == name);

            if ~isempty(idx)
                set(h.edits(idx), 'String', num2str(val));
            end

        elseif strcmp(strtrim(line),"Done")
            % On receiving "Done", stop the timer
            stop(h.timerObj); delete(h.timerObj);
            disp("Traffic cycle complete. All Clear.");
            return;
        end
    end
end

%% --- Process Green Path Message & Countdown
% This function handles the countdown during the green phase,
% updates the GUI text, and then calls the yellow transition.
function processGreenPathMessage(h, activePath, speedVal, greenTime, updatedCount)
    % Update the GUI immediately with the green light for activePath.
    updateLights(h, activePath);
    set(h.stateText, 'String', sprintf('Speed: %s cars/3s', speedVal));

    % Run a countdown loop displaying "Time Left"
    for t = greenTime:-1:1
        set(h.timerText, 'String', sprintf('Time Left: %ds', t));
        drawnow;
        pause(1);
    end

    % Update the car count for the active path after the green cycle.
    set(h.edits(activePath), 'String', num2str(updatedCount));
    
    % Now perform the yellow transition.
    performYellowTransition(h, activePath);
end

%% --- Perform Yellow Transition
% This function dims the green light, shows a bright yellow for 1 second,
% then reverts yellow to its dim state and resets all lights to red.
function performYellowTransition(h, activePath)
    % Dim the green light for the active path.
    set(h.lights(activePath).g, 'FaceColor', [0 0.3 0]);
    drawnow;
    
    % Set the yellow light to bright yellow.
    set(h.lights(activePath).y, 'FaceColor', 'yellow');
    drawnow;
    pause(1);   % Maintain yellow for 1 second

    % Revert the yellow light to its dim state.
    set(h.lights(activePath).y, 'FaceColor', [0.3 0.3 0]);
    drawnow;
    
    % Reset all lights to the red state.
    setAllRed(h);
    
    % Clear GUI text fields.
    set(h.timerText, 'String', '');
    set(h.stateText, 'String', '');
end

%% --- Update Lights
% Adjusts the light colors so that:
% - The active (green) path has a bright green, with dimmed yellow and red.
% - All other paths show bright red while their green and yellow remain dim.
function updateLights(h, activePath)
    for i = 1:4
        if i == activePath
            % Active path: set green as bright, yellow and red are dimmed.
            set(h.lights(i).g, 'FaceColor', 'green');    % bright green
            set(h.lights(i).y, 'FaceColor', [0.3 0.3 0]);  % dim yellow
            set(h.lights(i).r, 'FaceColor', [0.3 0 0]);      % dim red
        else
            % Inactive paths: red is bright, and green/yellow are dim.
            set(h.lights(i).g, 'FaceColor', [0 0.3 0]);      % dim green
            set(h.lights(i).y, 'FaceColor', [0.3 0.3 0]);    % dim yellow
            set(h.lights(i).r, 'FaceColor', 'red');          % bright red
        end
    end
    drawnow;
end

%% --- Set All Lights to Red
function setAllRed(h)
    for i = 1:4
        set(h.lights(i).r, 'FaceColor', 'red');
        set(h.lights(i).y, 'FaceColor', [0.3 0.3 0]);
        set(h.lights(i).g, 'FaceColor', [0 0.3 0]);
    end
    drawnow;
end

%% --- Callback: Stop
function onStop()
    figs = findall(0, 'Type', 'figure', 'Name','Traffic Signal GUI (PSoC Controlled)');
    if isempty(figs), return; end
    h = guidata(figs(1));
    if isfield(h, 'timerObj') && isvalid(h.timerObj)
        stop(h.timerObj); delete(h.timerObj);
    end
    if isfield(h, 'serialObj') && isvalid(h.serialObj)
        clear h.serialObj;
    end
end

%% --- Callback: Close
function onClose(src,~)
    h = guidata(src);
    if isfield(h, 'timerObj') && isvalid(h.timerObj)
        stop(h.timerObj); delete(h.timerObj);
    end
    if isfield(h, 'serialObj') && isvalid(h.serialObj)
        clear h.serialObj;
    end
    delete(src);
end
