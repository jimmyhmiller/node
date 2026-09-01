------------------------------ MODULE TSFNTeardown ------------------------------
EXTENDS Naturals

CONSTANT Fixed

States == {"Open", "Closing", "ResourceCleanup", "Closed"}
HandleStates == {"Open", "Closing", "Closed"}
CallbackPhases == {"None", "TSFNFinalizer", "ExternalFinalizer"}
LoopPCs == {"Idle", "InEnvUnref", "InExternalFinalizer", "AfterEnvUnref"}
Owners == {"External", "Native"}
Errors == {"None", "ReentrantLock"}

VARIABLES state,
          handle_state,
          owners,
          mutex,
          callback_phase,
          loop_pc,
          resources_released,
          env_unref_count,
          native_operation,
          delete_pending,
          delete_count,
          error

vars == <<state,
          handle_state,
          owners,
          mutex,
          callback_phase,
          loop_pc,
          resources_released,
          env_unref_count,
          native_operation,
          delete_pending,
          delete_count,
          error>>

Init == /\ state = "Open"
        /\ handle_state = "Open"
        /\ owners = Owners
        /\ mutex = "None"
        /\ callback_phase = "None"
        /\ loop_pc = "Idle"
        /\ resources_released = FALSE
        /\ env_unref_count = 0
        /\ native_operation = "None"
        /\ delete_pending = FALSE
        /\ delete_count = 0
        /\ error = "None"

BeginShutdown == /\ state = "Open"
                 /\ state' = "Closing"
                 /\ handle_state' = "Closing"
                 /\ UNCHANGED <<owners,
                                mutex,
                                callback_phase,
                                loop_pc,
                                 resources_released,
                                 env_unref_count,
                                 native_operation,
                                 delete_pending,
                                 delete_count,
                                error>>

CloseHandleCallback == /\ state = "Closing"
                       /\ handle_state = "Closing"
                       /\ handle_state' = "Closed"
                       /\ callback_phase' = "TSFNFinalizer"
                       /\ UNCHANGED <<state,
                                      owners,
                                      mutex,
                                      loop_pc,
                                       resources_released,
                                       env_unref_count,
                                       native_operation,
                                       delete_pending,
                                       delete_count,
                                      error>>

FinishTSFNFinalizer == /\ callback_phase = "TSFNFinalizer"
                       /\ callback_phase' = "None"
                       /\ UNCHANGED <<state,
                                      handle_state,
                                      owners,
                                      mutex,
                                      loop_pc,
                                       resources_released,
                                       env_unref_count,
                                       native_operation,
                                       delete_pending,
                                       delete_count,
                                      error>>

BeginResourceRelease == /\ state = "Closing"
                        /\ handle_state = "Closed"
                        /\ callback_phase = "None"
                        /\ loop_pc = "Idle"
                        /\ state' = IF Fixed THEN "ResourceCleanup" ELSE "Closed"
                        /\ mutex' = IF Fixed THEN "None" ELSE "Loop"
                        /\ loop_pc' = "InEnvUnref"
                        /\ resources_released' = TRUE
                        /\ env_unref_count' = env_unref_count + 1
                        /\ UNCHANGED <<handle_state,
                                       owners,
                                        callback_phase,
                                        native_operation,
                                        delete_pending,
                                        delete_count,
                                       error>>

BeginExternalFinalizer == /\ loop_pc = "InEnvUnref"
                          /\ "External" \in owners
                          /\ callback_phase = "None"
                          /\ callback_phase' = "ExternalFinalizer"
                          /\ loop_pc' = "InExternalFinalizer"
                          /\ UNCHANGED <<state,
                                         handle_state,
                                         owners,
                                         mutex,
                                         resources_released,
                                          env_unref_count,
                                          native_operation,
                                          delete_pending,
                                          delete_count,
                                         error>>

ExternalRelease == /\ callback_phase = "ExternalFinalizer"
                   /\ IF mutex = "Loop"
                         THEN /\ error' = "ReentrantLock"
                              /\ UNCHANGED <<owners,
                                             callback_phase,
                                             loop_pc>>
                         ELSE /\ owners' = owners \ {"External"}
                              /\ callback_phase' = "None"
                              /\ loop_pc' = "AfterEnvUnref"
                              /\ UNCHANGED error
                   /\ UNCHANGED <<state,
                                  handle_state,
                                  mutex,
                                  resources_released,
                                   env_unref_count,
                                   native_operation,
                                   delete_pending,
                                   delete_count>>

NativeRelease == /\ "Native" \in owners
                 /\ mutex = "None"
                 /\ owners' = owners \ {"Native"}
                  /\ native_operation' = "Release"
                  /\ IF state = "Closed" /\ owners = {"Native"}
                        THEN delete_pending' = TRUE
                        ELSE UNCHANGED delete_pending
                 /\ UNCHANGED <<state,
                                handle_state,
                                mutex,
                                callback_phase,
                                 loop_pc,
                                 resources_released,
                                 env_unref_count,
                                 delete_count,
                                 error>>

NativeClosingPush == /\ "Native" \in owners
                     /\ state \in {"Closing", "ResourceCleanup", "Closed"}
                     /\ mutex = "None"
                     /\ owners' = owners \ {"Native"}
                      /\ native_operation' = "Push"
                      /\ IF state = "Closed" /\ owners = {"Native"}
                            THEN delete_pending' = TRUE
                            ELSE UNCHANGED delete_pending
                     /\ UNCHANGED <<state,
                                    handle_state,
                                    mutex,
                                    callback_phase,
                                     loop_pc,
                                     resources_released,
                                     env_unref_count,
                                     delete_count,
                                     error>>

FinishResourceRelease == /\ Fixed
                         /\ state = "ResourceCleanup"
                         /\ loop_pc = "AfterEnvUnref"
                          /\ state' = "Closed"
                          /\ IF owners = {}
                                THEN delete_pending' = TRUE
                                ELSE UNCHANGED delete_pending
                         /\ UNCHANGED <<handle_state,
                                        owners,
                                        mutex,
                                        callback_phase,
                                        loop_pc,
                                         resources_released,
                                         env_unref_count,
                                         native_operation,
                                         delete_count,
                                         error>>

Destroy == /\ delete_pending
           /\ state = "Closed"
           /\ owners = {}
           /\ delete_pending' = FALSE
           /\ delete_count' = delete_count + 1
           /\ UNCHANGED <<state,
                          handle_state,
                          owners,
                          mutex,
                          callback_phase,
                          loop_pc,
                          resources_released,
                          env_unref_count,
                          native_operation,
                          error>>

Next == /\ error = "None"
        /\ delete_count = 0
        /\ (BeginShutdown
            \/ CloseHandleCallback
            \/ FinishTSFNFinalizer
            \/ BeginResourceRelease
            \/ BeginExternalFinalizer
            \/ ExternalRelease
            \/ NativeRelease
            \/ NativeClosingPush
            \/ FinishResourceRelease
            \/ Destroy)

Spec == Init /\ [][Next]_vars

TypeOK == /\ state \in States
          /\ handle_state \in HandleStates
          /\ owners \in SUBSET Owners
          /\ mutex \in {"None", "Loop"}
          /\ callback_phase \in CallbackPhases
          /\ loop_pc \in LoopPCs
          /\ resources_released \in BOOLEAN
          /\ env_unref_count \in Nat
          /\ native_operation \in {"None", "Release", "Push"}
          /\ delete_pending \in BOOLEAN
          /\ delete_count \in 0..1
          /\ error \in Errors

NoReentrantLock == error = "None"

ClosedAfterResources == state = "Closed" => resources_released

NoDeleteDuringCleanup == state = "ResourceCleanup" => delete_count = 0

DeleteDecisionSafe == delete_pending => /\ state = "Closed"
                                        /\ handle_state = "Closed"
                                        /\ owners = {}
                                        /\ resources_released
                                        /\ callback_phase = "None"
                                        /\ mutex = "None"

SafeDeletion == delete_count = 1 => /\ state = "Closed"
                                    /\ handle_state = "Closed"
                                    /\ owners = {}
                                    /\ resources_released
                                    /\ callback_phase = "None"

ResourcesReleasedOnce == /\ env_unref_count <= 1
                         /\ resources_released => env_unref_count = 1

=============================================================================
