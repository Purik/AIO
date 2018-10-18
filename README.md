
[https://www.facebook.com/aio.delphi](https://www.facebook.com/aio.delphi "Facebook official page")

# Introduction #

AIO implement procedural oriented programming (POP) style in Delphi. It means developer can combine advantages of OOP and POP, splitting logic to multiple state machines, schedule them to threads, connect them by communication channels like in GoLang, write CPU efficient I/O using high level abstractions of OS hardware objects avoiding platform specific non-blocking api calls like Completition ports in Windows world or select/poll/epoll calls in Linux world.


AIO put powerfull tool for building scalable applications in developer hands. Channels allow avoid necessity of manually transporting data samples with semaphores/mutexes/etc or through thread-safe queues. You can freely schedule, reschedule your state machines to threads/thread pools. Developer can easy concentrate his mind to buisness tasks, AIO engine will done all dirty job.

When used properly, you will see your programming code became more readable, more testable, more flexible and able to refactoring. This guide will help you.

**It's not joke, use modern approaches in Delphi today now !!!** 

AIO architecturally consists of 4 abstractions:

- **Greenlet(coroutine)**: state machine, that was runned on separate stack, with itself CPU state, developer can manually invoke coroutine to yield current thread resource to curoutine.  
- **Hub**: abstraction over scheduler, that keep list of greenlets, that it is owned, and afford interfaces for overlapped I/O operations.
- **AIO Provider**: abstraction over OS I/O object that provide ability to suspend current running context (coroutine) and switch to Hub to run another ready-to-work coroutine. When provider is ready for I/O operation, Hub will schedule CPU time to coroutine, that heve been initiating I/O operation though the provider.
- **Communication channel**: sync/async data channel, provide ability to share data between state machines.

# Most frequently asked questions #


1. **Q**: Why you named coroutine "greenlet" ?  
   **A**: "Coroutine" is very weak abstraction. If you pay attention to several implementantion of coroutines in just libraries/languages as **C++ Boost**, **LUA**, **Go lang**, etc, you will see there is big variety of implementations. **"Greenlet"** is coroutine with fixed interface: 
**switch** method for calling greenlet (with ability to send arguments and wait result tuple of data), **yield** method to return context to caller, **kill** method to immediately terminate greenlet, herewith system will call all **finally** sections in try-finally blocks, it can be usefull to guarantee free resources locally allocated inside greenlet.
2. **Q**: What is difference between sync and async channels, when is it sane to use sync and what is advantages of async channels ?  
   **A**: If you don't understand what kind of channel to use - use sync channels (by default), i.e. use channel with 0 buffer size. When you send data sample to sync channel, it immediatelly yield current context and switch to context of any data consumer who wait data on another side of channel or suspend current context for future when data consumer will appear. Internally channels use private interfaces of hubs and greenlets to suspend/resume consumers/producers. Opposite sync ideology, you should use async channel if you work with hardware objects (socket, com, etc) that have an async nature and internal I/O buffers. In many cases using sync channels is more simple than async channels.
3. **Q**: Why I should use AIO providers instead of direct call current hub interfaces (Write, Read, etc) ?  
   **A**: You can call current hub (hub that is sheduling running context) directly, but you should be ready to work with OS native platform specific api. AIO providers hide platform-specific OS calls for different hardware objects: tcp/udp sockets, com-ports, sound cards, console in/out, named pipes, etc and when you call Read/Write procedures, aio provider internally call relative Hub calls to put object descriptor/handle to OS multiplexor to resume calling context in the future, when I/O object will be ready to finish overlapped operation.
4. **Q**: Why your implementation of greenlets is based on records? Not classes/interfaces ?  
   **A**: There is Automatic reference counting in Delphi, but this approach doesn't work for all platforms. For example, auto ref counting doesn't work for Winfows platform compiler. Obvious decition to make this is to use interfaces, but using interfaces mean developer must keep in mind what implementation class instance he must create to assign to interface variable at first, besides interfaces don't support namespaces to declare specific constants or internal types at second, and record can incapsulate inside its calls specific "magic" with implementation classes at third, polimorphism of clases and interfaces can be implemented in records by Implicit assigning, for POP style polimorphism is not so important as for OOP.

# Tutorial

## Part 1. Greenlets

1. **Methods**

     * Switch - call greenlet to let it run until yield will be called obviously
     * Yield - return to caller context
     * Kill - termitate greenlet with guarantee of calling finally block of try-finally sections
        
2. **Symmetric**
        
    TSymmetric<T1, T2,...Tn> - greenlet with explicit typed input arguments. 

    See demo: [Demos\Tutorial\Symmetric.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/Symmetric.dpr "Demos\Tutorial\Symmetric.dpr")
    
        {$APPTYPE CONSOLE}
          ....
        var 
          S: TSymmetric<Integer>;
          Proc: TSymmetricRoutine<Integer>;
        
        begin

          Proc := procedure(const Input: Integer)
          var
            Internal: Integer;
          begin
            WriteLn('Input value: ', Input);
            try
              Internal := Input;
              while True do 
              begin
                Yield;  // return to caller context
                Inc(Internal);
                WriteLn('Internal = ', Internal);
              end
            finally
              WriteLn('Execution is terminated...')
            end
          end;
  
          S := TSymmetric<Integer>.Create(Proc, 10);

          // Manually call to Switch is not thread safe so this call is not declared
          // in Symmetric interface
          with IRawGreenlet(S) do
          begin
            Switch;
            Switch;
            Switch;
          end;
          S.Kill;
          ...
        end.

    Output:

        Input value: 10
        Internal = 11
        Internal = 12
        Execution is terminated...


    Difference between **Spawn** and **Create** constructor calls: when you create symmetric with **Spawn**, symmetric is calling immediately, when you create symmetric by **Create**, it has status "Ready" - it is not started until "Switch" call.

    See demo: *Demos\Tutorial\SpawnVsCreate.dpr*
        
        ...        
        var 
          S1, S2: TSymmetric<string>;
          Proc: TSymmetricRoutine<string>;
        begin
          Proc := procedure(const Name: string)
          begin
            try
              while True do
              begin
                WriteLn(Format('Greenlet "%s" is called!', [Name]));
                Yield;
              end
            finally
              WriteLn(Format('Greenlet "%s" is terminated!', [Name]));
            end
          end;

          S1 := TSymmetric<string>.Create(Proc, 'greenlet 1');
          S2 := TSymmetric<string>.Spawn(Proc, 'greenlet 2');

          Assert(IRawGreenlet(S1).GetState = gsReady);
          Assert(IRawGreenlet(S2).GetState = gsExecute);
          S2.Kill;
          Assert(IRawGreenlet(S2).GetState = gsKilled);
          IRawGreenlet(S1).Switch;
          Assert(IRawGreenlet(S1).GetState = gsExecute);
        ...

        end;

        === Output: ===
        Greenlet "greenlet 2" is called!
        Greenlet "greenlet 2" is terminated!
        Greenlet "greenlet 1" is called!


3. **Asymmetric**
    
    TAsymmetric<T1, T2,...Tn, RET> - greenlet with explicit typed input arguments **[T1...Tn]** and has return value with type **RET**.
        
      example: Arithmetic progression. 

      see demo: [Demos\Tutorial\Asymmetric.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/Asymmetric.dpr "Demos\Tutorial\Asymmetric.dpr")
        
        {$APPTYPE CONSOLE}
        .....
        var 
          A: TAsymmetric<Integer, Integer, Integer, string>;
          Func: TAsymmetricRoutine<Integer, Integer, Integer, string>;
   
        begin

          Func := function(const Start, Step, Stop: Integer): string
          var
            Cur, Accum: Integer;
          begin
            WriteLn(Format('Input parameters: Start = %d; Step = %d; Stop = %d', [Start, Step, Stop]));
            Cur := Start;
            Accum := Start;

            while Cur <= Stop do
            begin
              WriteLn(Format('Cur = %d', [Cur]));
              Yield;
              Inc(Cur, Step);
              Inc(Accum, Cur)
            end;
            Result := Format('Result = %d', [Accum]);
          end;

          A := TAsymmetric<Integer, Integer, Integer, string>.Create(Func, 10, 3, 17);
          while IRawGreenlet(A).GetState <> gsTerminated do
            IRawGreenlet(A).Switch;
          // if you call GetResult before asymmetric is terminated, exception will be raised
          WriteLn(Format('A.GetResult = "%s"', [A.GetResult]));

        end.

    Output:

        Input parameters: Start = 10; Step = 3; Stop = 17
        Cur = 10
        Cur = 13
        Cur = 16
        A.GetResult = "Result = 58"


    Difference between **Spawn** and **Create** constructor calls: when you create asymmetric with **Spawn**, asymmetric is calling immediately, when you create asymmetric by **Create**, it has status "Ready" - it is not started until "Switch" call.

    If you call method **GetResult** of asymmetric while it is not terminated, exception will be raised.

4. **Greenlet with varianted args**

    Sometimes developer need to operate TVarArg parameners. To do so there is TGreenlet.

    See demo: [Demos\Tutorial\GreenletVarArgs.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/GreenletVarArgs.dpr "Demos\Tutorial\GreenletVarArgs.dpr")

        var
          G: TGreenlet;
          Routine: TSymmetricArgsRoutine;

        begin
          Routine := procedure(const Args: array of const)
          var
            I: Integer;
          begin
            WriteLn('Greenlet context enter');
            for I := Low(Args) to High(Args) do
            begin
              // you can check type of VarArg and cast to type
              if Args[I].IsInteger then
                Write(Format('Arg[%d] = %d; ', [I, Args[I].AsInteger]))
              else if Args[I].IsString  then
                Write(Format('Arg[%d] = "%s"; ', [I, Args[I].AsString]))
              else
                Write(Format('Arg[%d] - unexpected type', [I]))
            end;
            WriteLn;
            WriteLn('Greenlet context leave');
          end;

          G := TGreenlet.Spawn(Routine, [1, 'hello!', 5.6]);

        end.

    Output:

        Greenlet context enter
        Arg[0] = 1; Arg[1] = "hello!"; Arg[2] - unexpected type
        Greenlet context leave


5. **Generator**
    
    Generator is very useful syntaсtic sugar in many languages, it is time when you can use it in Delphi now. No more words only example...   

    See demo: [Demos\Tutorial\Generator.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/Generator.dpr "Demos\Tutorial\Generator.dpr")

        {$APPTYPE CONSOLE}
        uses Greenlets;
        ...
        var
          Gen: TGenerator<Integer>;
          Iter: Integer;
          Routine: TSymmetricArgsRoutine
        
        begin
          
          Routine := procedure(const Args: array of const)
          var
            Start, Stop, Step, Cur: Integer;

          begin
            Start := Args[0].AsInteger;
            Step  := Args[1].AsInteger;
            Stop  := Args[2].AsInteger;
            Cur := Start;
            while Cur <= Stop do
            begin
              // Here we yield data out of routine context
              TGenerator<Integer>.Yield(Cur);
              Inc(Cur, Step);
            end; 
          end;

          Gen := TGenerator<Integer>.Create(Routine, [10, 3, 18]);
          // enum generator values across for-in loop
          for Iter in Gen do
            WriteLn(Format('Iter = %d', [Iter]));
  
        ...
        end.

    Output:
        
        Iter = 10
        Iter = 13
        Iter = 16


    Generator implements IEnumerable interface, so you can use it in **for in** sections.

    Generator is usefull in cases when you need enum big sequence provided by an algorithm and data amount is too large memory to keep all data in List or other collection.

6. **Join multiple greenlets**

    Sometimes program logic assumes splitting to multiple parallel state machines at first step and waiting for all of them are completed at second. Moreover we would like control if exception was raised in one of them. 

    To do this you should use **Join** call with ability set timeout and set flag of reraising exceptions.

    See demo: [Demos\Tutorial\JoinN.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/JoinN.dpr "Demos\Tutorial\JoinN.dpr") 

        {$APPTYPE CONSOLE}
        uses Greenlets;
        ...
        var
          Routine: ..
        begin

          Routine := procedure(const Counter: Integer; const RaiseAbort: Boolean)
          var 
            I: Integer;
          begin
            for I := 1 to Counter do
              Yield;
            if RaiseAbort then
              Abort;
          end;

          try
            // exception raised in greenlets will be reraised to caller context
            Join([
              TSymmetric<Integer, Boolean>.Spawn(Routine, 100, False),
              TSymmetric<Integer, Boolean>.Spawn(Routine, 1000, False),
              TSymmetric<Integer, Boolean>.Spawn(Routine, 10000, True)
            ], INFINITE, True)
          except on Exception as E do begin
            WriteLn(Format('Exception %s was raised', [E.ClassName]))
          end
        ...
        end.

    Output:
    
        Exception EAbort was raised

    You can use **JoinAll** call to join all greenlets, registered in current Hub. 
 

7. **Select one from multiple greenlets**

    Sometimes program logic assumes splitting to multiple parallel state machines at first step and waiting for one of them is completed at second. Moreover we would like control if exception was raised in one of them and take ability to know what greenlet was signaled. 

    To do this you should use **Select(array of greenlets, Index)** call.

    See demo: [Demos\Tutorial\SelectN.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/SelectN.dpr "Demos\Tutorial\SelectN.dpr")

        {$APPTYPE CONSOLE}
        uses Greenlets;
        ...
        var
          Routine: TSymmetricRoutine<Integer>;
          Index: Integer;
        begin

          Routine := procedure(const Timeout: Integer)
          begin
            GreenSleep(Timeout);
          end;

          Greenlets.Select([
            TSymmetric<Integer>.Spawn(Routine, 1000),
            TSymmetric<Integer>.Spawn(Routine, 100),
            TSymmetric<Integer>.Spawn(Routine, 10000)
          ], Index);
 
          WriteLn(Format('Greenlet with index = %d is terminated first', [Index]));

        ...
        end.

    Output:

        Greenlet with index = 1 is terminated first

8. **Scheduling symmetrics/asymmetrics to other threads**

    When you create Greenlet (Symmetric/Asymmetric) by Create/Spawn constructor, new greenlet is scheduling to current hub, in other words, new greenlet will be executed in same thread (thread pool) when you making call to Create/Spawn. 

    Sometimes, developer wish to schedule new greenlet explicitly to known thread. It is sane, for example, if greenlet progress high CPU mathematic. 

    See demo: [Demos\Tutorial\Scheduling.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/Scheduling.dpr "Demos\Tutorial\Scheduling.dpr")
    

        {$APPTYPE CONSOLE}
        function Fibonacci(N: Integer): Integer;
        begin
          if N < 0 then
            raise Exception.Create('The Fibonacci sequence is not defined for negative integers.');
          case N of
            0: Result:= 0;
            1: Result:= 1;
          else
            Result := Fibonacci(N - 1) + Fibonacci(N - 2);
          end;
        end;

        function ThreadedFibo(const N: Integer): string;
        begin
          Result := Format('Thread %d. Fibonacci(%d) = %d',
            [TThread.CurrentThread.ThreadID, N, Fibonacci(N)])
        end;

        var
          F1, F2, F3: TAsymmetric<string>;
          OtherThread: TGreenThread;

        OtherThread := TGreenThread.Create;
        try
          F1 := OtherThread.Asymmetrics<string>.Spawn<Integer>(ThreadedFibo, 10);
          F2 := OtherThread.Asymmetrics<string>.Spawn<Integer>(ThreadedFibo, 20);
          F3 := OtherThread.Asymmetrics<string>.Spawn<Integer>(ThreadedFibo, 30);
  
          Writeln(Format('F1.GetResult = "%s"', [F1.GetResult]));
          Writeln(Format('F2.GetResult = "%s"', [F2.GetResult]));
          Writeln(Format('F3.GetResult = "%s"', [F3.GetResult]));


        finally
          OtherThread.Free
        end; 

    Output:

        F1.GetResult = "Thread X. Fibonacci(10) = 55"
        F2.GetResult = "Thread X. Fibonacci(20) = 6765"
        F3.GetResult = "Thread X. Fibonacci(30) = 832040"

9. **BeginThread/EndThread as implicit scheduling to new thread**
   
     Developer can switch workflow to other thread implicitly.

     See demo: [Demos\Tutorial\BeginEndThread.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/BeginEndThread.dpr "Demos\Tutorial\BeginEndThread.dpr")

        function Fibonacci(N: Integer): Integer;
        begin
          if N < 0 then
            raise Exception.Create('The Fibonacci sequence is not defined for negative integers.');
          case N of
            0: Result:= 0;
            1: Result:= 1;
          else
            Result := Fibonacci(N - 1) + Fibonacci(N - 2);
          end;
        end;

        var
          F1, F2, F3: TAsymmetric<Integer, string>;
          ThreadedFibo: TAsymmetricRoutine<Integer, string>;

        begin

          ThreadedFibo := function(const N: Integer): string
          var
            Thread1, Thread2, Thread3: LongWord;
            Fibo: Integer;
          begin
            Thread1 := TThread.CurrentThread.ThreadID;
            // Switch to New thread
            BeginThread;
            Thread2 := TThread.CurrentThread.ThreadID;
            // calculation in context of other thread
            Fibo := Fibonacci(N);

            // return to caller thread
            // It is usefull if you have initiated process in MainThread for example
            // and after that you wish return to Main thread and Paint results on GUI
            EndThread;
            Thread3 := TThread.CurrentThread.ThreadID;
  
            Result := Format('Fibo(%d) = %d;  Thread1=%d, Thread2=%d, Thread3=%d',
              [N, Fibo, Thread1, Thread2, Thread3]);
          end;


          F1 := TAsymmetric<Integer, string>.Spawn(ThreadedFibo, 10);
          F2 := TAsymmetric<Integer, string>.Spawn(ThreadedFibo, 20);
          F3 := TAsymmetric<Integer, string>.Spawn(ThreadedFibo, 30);
  
          Join([F1, F2, F3]);

          Writeln(Format('F1.GetResult = "%s"', [F1.GetResult]));
          Writeln(Format('F2.GetResult = "%s"', [F2.GetResult]));
          Writeln(Format('F3.GetResult = "%s"', [F3.GetResult]));

        end

    Output: you can see **Thread2** is allways differ cause of context is switching to new threads

        F1.GetResult = "Fibo(10) = 55;  Thread1=x, Thread2=..., Thread3=x"
        F2.GetResult = "Fibo(20) = 6765;  Thread1=x, Thread2=..., Thread3=x"
        F3.GetResult = "Fibo(30) = 832040;  Thread1=x, Thread2=..., Thread3=x"


10. **GreenSleep**

    There is Delphi system call **Sleep(N)** that suspend current thread for N milliseconds. You should not use this call in Greenlet environment. You should replace **Sleep** calls to **GreenSleep** calls. 

    The reason of this is following. Any thread of your process is scheduling by OS, so, when you call **Sleep**, system scheduler switch thread to "Suspend" state and take off it from scheduling queue until timeout is end. Greenlets are scheduled by **Hub** in thread context, that means when Yield is called in greenlet[1], Hub will schedule CPU resource (in context of ownered thread) to greenlet[N] that have state "Executed". As a result, we get Two-level scheduling: first level - os level, second level - internal scheduling in Hubs. So if you call **Sleep** system call, you deprive Hub ability schedule owned greenlets.

        {$APPTYPE CONSOLE}
        uses Greenlets;
        ...
        var
          Stamp: TTime;
          Hours, Mins, Secs, MSecs: Word;
          Routine: ...

        begin

          Routine := procedure(const Delay: Integer)
          begin
			GreenSleep(Delay);
          end;

          Stamp := Now;
          Join([
            TSymmetric<Integer>.Spawn(Routine, 1000),
            TSymmetric<Integer>.Spawn(Routine, 1000),
            TSymmetric<Integer>.Spawn(Routine, 1000)
          ]);
          DecodeDateTime(Now - Stamp, Hours, Mins, Secs, MSecs);

          WriteLn(Format('Multiple execution took %d sec, %d msec', [Secs, MSecs]))
        ...
        end. 

    Output: output can be few differenced according you PC and enthropy behavor.

        Multiple execution took 1 sec, 2 msec

    If you will replace **GreenSleep** to **Sleep**, result will be dramatical )) 

11. **MonkeyPatching**

    Delphi is powerfull tool for GUI developing. Examples above are written for console variant cause of workflow in console application has one way direction. In GUI application, as you know, MainThread serve gui message queue and raise GUI controls callbacks, registered for specific messages. 

    To run Greenlets magic in GUI behaviour there is two approaches:
      
      1. Rewrite  MainThread message loop calls to `GetCurrentHub.Serve`
      
      2. Call to MonkeyPatches module, it contains calls that intercept OS api calls for managing message queue and replace it to OS multiplexor calls.

     

    See demo: [AIO\Demos\Tutorial\MonkeyPatching.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/MonkeyPatching.dpr "Demos\Tutorial\MonkeyPatching.dpr")
        
        uses 
          ... Greenlets, MonkeyPatch ... ;
        .....

        TMainForm = class(TForm)
          ...
          procedure StartTimerBtnClick(Sender: TObject);
          ...
        private
          FTimer: TSymmetric<Integer>;
          ...
        end;
 
        ..... 
         

        procedure TMainForm.StartTimerBtnClick(Sender: TObject);
        var
          Routine: TSymmetricRoutine<Integer>;
        begin

          Routine := procedure(const Interval: Integer)
          var
            Counter: Integer;
          begin
            Counter := 0;
            try
              while True do
              begin
                TimerLabel.Caption := IntToStr(Counter);
                Inc(Counter);
                GreenSleep(Interval)
              end;
            finally 
              TimerLabel.Caption := 'Terminated'
            end;
          end;

          FTimer := TSymmetric<Integer>.Spawn(Routine, StrToInt(IntervalEdit.Text));

          ...

        end;

        ........
        initialization
          // Afterr calling this method you can use Greenlets engine in GUI
          // as native mechanism
          MonkeyPatch.PatchWinMsg(True);
        .......


## Part 2. Channels

1. **Lifecycle, channels interface**

    Communication channels are powerfull tool that allows to share data between state machines in procedural style. Developer can build scalable multithreaded logic.
    
    Channel can has only two states:
      1. Active: you can write/read to/from channel
      2. Closed: every time you call read/write it will returns False
      
    You can't reactivate channel, when anyone call **Close** noone can send data samples to channel or read from one.

    Channel has very simple interface:
      1. **Read** method: suspend executor until data is appeared in channel. False will be returned if channl was closed.
      2. **Write** method: send data sample to channel or suspend executor until channel is ready to accept data. False will be returned if channl was closed.
      3. **Close** method: close channel. If there is any data in channel buffer, consumers will have ability to read them until buffer will have 0 size and read call will return False. If channel is closed, no producer can write data to it, write call will return False. 

2. **Use cases**

    Let's take a view to data sharing across communication channels

    See demo: [Demos\Tutorial\PingPong1.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/PingPong1.dpr "Demos\Tutorial\PingPong1.dpr")

        type
          TPingPongChannel = TChannel<Integer>;
        const
          PING_PONG_COUNT = 1000;
        var
          Channel: TPingPongChannel;
          Pinger: TSymmetric<TPingPongChannel>;
          Ponger: TSymmetric<TPingPongChannel>;
          
        begin
          // create channel for data transferring
          Channel := TPingPongChannel.Make;

          // create ping/pong workers
          Pinger := TSymmetric<TPingPongChannel>.Spawn(
		    procedure(const Chan: TPingPongChannel)
		    var
		      Ping, Pong: Integer;
		    begin
		      for Ping := 1 to PING_PONG_COUNT do
		      begin
		        Chan.Write(Ping);
		        Chan.Read(Pong);
		        Assert(Ping = Pong);
		      end;
		      Chan.Close;
		    end,
		    // put channel as argument
		    Channel
		  );

		  Ponger := TSymmetric<TPingPongChannel>.Spawn(
		    procedure(const Chan: TPingPongChannel)
		    var
		      Ping: Integer;
		    begin
		      while Chan.Read(Ping) do
		        Chan.Write(Ping)  // echo ping
		    end,
		    // put channel as argument
		    Channel
		  );

          // wait until ping-pong is terminated
          Join([Pinger, Ponger]);
          
        end

    Channels implement IEnumerable interface, so we can rewrite ponger to same manner:

    See demo: [Demos\Tutorial\PingPong2.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/PingPong2.dpr "Demos\Tutorial\PingPong2.dpr")

        Ponger := TSymmetric<TPingPongChannel>.Spawn(
            procedure(const Chan: TPingPongChannel)
            var
              Ping: Integer;
            begin
              // channel will automatically break for in loop when channel is closed.  
              for Ping in Chan do
                Chan.Write(Ping)
            end
          );

    Lets's take view to example below: making pizza.

    We have pizza order flow. Suppose customer make choice of sauces. Every sauce is implemented by specific greenlet.

        ...
    

3. **Sync channels**

    Sync channel is channel without buffer. It means when producer write data to channel, channel suspend executor until  any consumer will appear on other side of channel. Sync channel is very fast if producers/consumers are scheduled by single Hub, cause of sync channel can switch greenlets one to another avoiding Hub interfaces, just approach minimize count of calls to hub raising perfomance.

    Moreover, it is very simple to debug state machines that communicate through sync channel: debugging workflow has single line direction, you can be sure when you debug code in state machine N1, code in state machine N2 is not executing.

    How to create Sync channel:

        MyChannel := TChannel<Integer>.Make;  

    See demo: [Demos\Tutorial\SyncChannels.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/SyncChannels.dpr "Demos\Tutorial\SyncChannels.dpr")

4. **Async channels**

    Async channel is channel with buffer. Developer set buffer size through constructor parameter, after async channel is created, it is no ability to change buffer size. When producer send data sample to async channel, executing context will not be suspended until async channel buffer is overflow, consumers can read data from async channel asynchroniously. As soon as async channel buffer is overflowed, any effort to write data to it will cause suspending producer executing context. 

    To debug async channel is more harder than sync channel but it is sense to use async channels if greenlets are scheduled in separate threads or you have to develop hardware that has asynchronious nature (driver buffers and hardware buffers is typical behaviour)

    In other words, async channel is analogue of transaction memory approach. Keep it in mind.

    How to create Sync channel:

        MyChannel := TChannel<Integer>.Make(N);  // where N is buffer size > 0  

    See demo: [Demos\Tutorial\AsyncChannels.dpr](https://github.com/Purik/AIO/blob/master/Demos/Tutorial/AsyncChannels.dpr "Demos\Tutorial\AsyncChannels.dpr")

5. **Class instances as data samples and references counting problem**

    Channels allow pass data between state machines regardless of thread context. When you put data sample to channel you have not ability to control it anymore. It is not problem if you transferring primitive data (integers, floats) or data of memory managed types (string, dynamic array) or data of autoref types like interfaces. But Delphi is object oriented language and it is sense to send class instances as data. Modern delphi compilers have auto refs counting mechanisms but not for all platforms (windows compiler doesn't support that). To solve this challenge for specific platforms AIO engine has internal reference counting mechanism through TSmartPointer data type. Developer doesn't have to keep in mind this magic. 

>    **All you have to remember** - 
> when you send class instance to channel, you don't have to call destructor manually, since this moment AIO automatically destroy object as soon as no one context keep reference to it. 

6. **Delayed read/write operations**
    
    It is usefull to implement delayed Read/Write operations for multiple channels 

## Part 3. AIO Providers

1. **Introduction to AIO providers**

    AIO providers are abstractions over os I/O non-blocking APIs. It is more difficult to write and debug non-blocking read/write operations. Different operating systems have different implementations and nuances of implementation. For example, Windows non-blocking operations are based on completition ports. Main point of completition ports is api signal of succesfull operation **after** read/write operation was completed. As opposed to Windows completition ports, Linux multiplexor API like poll/epoll calls raise signal **before** operation completed, i.e. driver is ready to accept part of data. Similar differences bring problems when developer have to write I/O CPU efficient code, non-blocking operations originally are very efficient.

    Good news (among problems, depicted above) broke into lifes of Delphi developers! 
      1. State machines idiom hide differences of multiple non-blocking implementations of various OS. 
      2. State machines idiom allow write programming code in simple block style with most high OS resources utilizations.
    
    Aio providers internally suspend caller greenlet after I/O operation is runned and set resume callbacks for resuming caller greenlets when I/O operation is completed. So, developer write programming code in block-style while really hardware operations are processed by OS in non-blocking mode. **It's great!!!**

    All AIO providers are declared in Aio module.

2. **TCP/UDP socket**

     Example: read HTML content from multiple sites

        type
          TURL = string;
          THTML = string;
          TWorker = TAsymmetric<TURL, THTML>;

        var
          Job: TDictionary<TURL, TWorker>;
          Routine: ...
          
        begin

          Routine := function(const URL: TURL): THTML
          var
            Sock: IAioTcpSocket;
            Partial: THTML;
          begin
            Sock := MakeAioTcpSocket;
            // timeout 1 sec
            if Sock.Connect(URL, 1000) then
            begin
              Sock.Write('GET /');
              // AIO providers implement basic string parsing interfaces
              // Read all Lines from remote source
              for Partial in Sock.ReadLns do
                Result := Result + Partial
            end
            else
              Result := 'Connection error.'   
          end;

          Job := TDictionary<TURL, TWorker>.Create;
          try
            ...
          finally
            Job.Free;
          end

        end

3. **COM port**

    Example: Send command to remote device across COM port interface. 

        var
          Com: IAioComPort;

        begin

          Com := MakeAioComPort;
          ...
        end 

4. **Named pipes**

        var
		  ServerPipe, ClientPipe: IAioNamedPipe;
		  Producer, Consumer: TSymmetric<IAioProvider>;

		begin
		  ServerPipe := Aio.MakeAioNamedPipe('MyPipeName');
		  ServerPipe.MakeServer;
		  ClientPipe := Aio.MakeAioNamedPipe('MyPipeName');
		  ClientPipe.Open;
		
		  Producer := TSymmetric<IAioProvider>.Spawn(
		    procedure(const Prov: IAioProvider)
		    begin
		      Prov.WriteLn('Message 1');
		      Prov.WriteLn('Message 2');
		      Prov.WriteLn('Done');
		    end,
		
		    ServerPipe
		  );
		
		  Consumer := TSymmetric<IAioProvider>.Spawn(
		    procedure(const Prov: IAioProvider)
		    var
		      S: string;
		    begin
		      for S in Prov.ReadLns do begin
		        Writeln(Format('Consumer received text: "%s"', [S]));
		        if S = 'Done' then
		          Exit
		      end;
		    end,
		
		    ClientPipe
		  );
		
		  Join([Producer, Consumer]);
		  Write('Press Any key');
		  ReadLn;
		
		end.

5. **Call console applications and communicate with remote process by stdin, stdout, stderr pipes**

        var
		  Console: IAioConsoleApplication;
		  Line: string;

        begin
		  Console := MakeAioConsoleApp('tasklist', []);
		  for Line in Console.StdOut.ReadLns do
		    WriteLn(Line)
		  ....
		end.

6. **Files**

        var
  		  F: IAioFile;
        begin
		  F := MakeAioFile('MyFile.txt', fmOpenReadWrite);
		  ...
		end.

## Part 4. Conclusion

   Every developer began study of writing programs by simplest examples of console applocations. Basically it is native to human way of thinking. Modern world put an engineer in behaviour of multiple entities with difficult natures and with necessity share states and data. There is large count of frameworks that helps developer build complex systems with minimum efforts. You can see large amount of use cases and approaches: callbacks, queues, signal/slots, reactive extensions and many others. Thuth be told, all of them assume developer must keep in mind some amount of idioms and assumptions. Approach based on state machine in procedural style is the most nearest to human way of thinking - it's pure imperative Turing machine (Alan Turing) with self allocated stack stack to keep local variables and self CPU registers to keep states. 

   It doesn't mean you have to throw away OOP and known frameworks, but very often it is sense to build architecture of project as combination of multiple state machines and connect them each other by communication channels to share states/data in multithread/multiprocess/multimachine environment. When used properly, this approach allow build more manageable and more testable projects cause it is more easily to manage small part of algorithm encapsulated in separate state machine than manage complex mix of different entities. **You can combine advantages of AIO and your favorite frameworks/libraries**. 

   Procedural oriented style can be usefull when you have to build telecommunication system, when you have to work with multiple data streams, for example, in multimedia project. Procedural approach resolve basic disadvantage of OOP paradigm - object is passive entity, it wait until someone will call its interfaces. In telecommunication and multimedia delivery system developer is engaged in entites of active nature: sockets, hardware devices, etc. Sometimes efforts to describe active entities in OOP paradigm seems less obvious and clear than POP.

   

## Part 5. Features to be implemented

   1. **Thread Pools** - this approach allow scale state machines over CPU resource more transparently than manually schedule greenlets to threads.
   2. **Cross platform** - current version supports only Windows platform. Core of aio has only two platform specific points: 
     * **switch/yield** contexts, this challenge can be resolved simply by Boost Context library
     * **non-blocking I/O** calls for AIO providers and Hubs. There is large amount of production-ready libraries that implement abstractions over variety OS API calls.  
   3. **Non-blocking Indy** - Indy library allow declare self I/O handlers and inject them to Indy Components. It is sense to implement AIO friendly handlers to allow developer use powerfull Indy Clients/Servers in greenlets. 
  


# HowTo guides

* **Generators**  [Demos\HowTo\GeneratorsForm.pas](https://github.com/Purik/AIO/blob/master/Demos/HowTo/GeneratorsForm.pas)

* **Http Client** [Demos\HowTo\HowTo.HttpClient.dpr](https://github.com/Purik/AIO/blob/master/Demos/HowTo/HowTo.HttpClient.dpr)

* **Greenlets**
   
    TODO

* **Local contexts**

    TODO

* **Symmetrics**
    
    TODO

* **Asymmetrics**
    
    TODO

* **Gevents**

    TODO

* **Channels**
    
    TODO

* **Channel buffering**
    
    TODO

* **Channel Synchronization**
   
    TODO

* **Channel Directions**
   
    TODO

* **Non-blocking channel operations**
   
    TODO

* **Timeouts**
   
    TODO

* **Closing channels**
   
    TODO

* **Range over Channels**
   
    TODO

* **Timers**
   
    TODO

* **GreenGroup**
   
    TODO

* **CondVariable**

    TODO

* **Semaphores**

    TODO

* **Queues**

* **FanOut**

    TODO

* **Generators**

    TODO

* **Scheduling to other Thread**

    TODO

* **Implicit scheduling to new thread**

    TODO

* **TCP echo server**

    TODO 

# Technical references

1. **Cooparative multitasking in a nutshell**

    TODO

2. **Internal organization of greenlet**

    TODO

3. **Excaption raised in greenlet context**

    TODO

4. **Greenlet termination. Internal organization**

    TODO

5. **Hub**

    TODO

6. **Hub and non-blocking operations**

    TODO

 