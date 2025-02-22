import Distribution.PackageDescription
import Distribution.PackageDescription.Parse
import Distribution.Simple
import Distribution.Simple.BuildPaths
import Distribution.Simple.Command
import Distribution.Simple.Program.Db
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.PreProcess           hiding (ppC2hs)
import Distribution.Simple.Program
import Distribution.Simple.Setup
import Distribution.Simple.Utils
import Distribution.System
import Distribution.Verbosity

import Control.Exception
import Control.Monad
import Data.Function
import Data.List                                hiding (isInfixOf)
import Data.Maybe
import System.Directory
import System.Environment
import System.Exit                              hiding (die)
import System.FilePath
import System.IO.Error                          hiding (catch)
import Text.Printf
import Prelude                                  hiding (catch)


newtype CudaPath = CudaPath { cudaPath :: String }
  deriving (Eq, Ord, Show, Read)


-- Windows compatibility function.
--
-- CUDA toolkit uses different names for import libraries and their
-- respective DLLs. For example, on 32-bit architecture and version 7.0 of
-- toolkit, `cudart.lib` imports functions from `cudart32_70`.
--
-- The ghci linker fails to resolve this. Therefore, it needs to be given
-- the DLL filenames as `extra-ghci-libraries` option.
--
-- This function takes *a path to* import library and returns name of
-- corresponding DLL.
--
-- Eg: "C:/CUDA/Toolkit/Win32/cudart.lib" -> "cudart32_70.dll"
--
-- Internally it assumes that 'nm' tool is present in PATH. This should be
-- always true, as 'nm' is distributed along with GHC.
--
-- The function is meant to be used on Windows. Other platforms may or may
-- not work.
--
importLibraryToDllFileName :: FilePath -> IO (Maybe FilePath)
importLibraryToDllFileName importLibPath = do
  -- Sample output nm generates on cudart.lib
  --
  -- nvcuda.dll:
  -- 00000000 i .idata$2
  -- 00000000 i .idata$4
  -- 00000000 i .idata$5
  -- 00000000 i .idata$6
  -- 009c9d1b a @comp.id
  -- 00000000 I __IMPORT_DESCRIPTOR_nvcuda
  --          U __NULL_IMPORT_DESCRIPTOR
  --          U nvcuda_NULL_THUNK_DATA
  --
  nmOutput <- getProgramInvocationOutput normal (simpleProgramInvocation "nm" [importLibPath])
  return $ find (isInfixOf ("" <.> dllExtension)) (lines nmOutput)

-- Windows compatibility function.
--
-- The function is used to populate the extraGHCiLibs list on Windows
-- platform. It takes libraries directory and .lib filenames and returns
-- their corresponding dll filename. (Both filenames are stripped from
-- extensions)
--
-- Eg: "C:\cuda\toolkit\lib\x64" -> ["cudart", "cuda"] -> ["cudart64_65", "ncuda"]
--
additionalGhciLibraries :: FilePath -> [FilePath] -> IO [FilePath]
additionalGhciLibraries libdir importLibs = do
  let libsAbsolutePaths = map (\libname -> libdir </> libname <.> "lib") importLibs
  candidateNames <- mapM importLibraryToDllFileName libsAbsolutePaths
  let dllNames = map (\(Just dllname) -> dropExtension dllname) (filter isJust candidateNames)
  return dllNames

-- Mac OS X compatibility function
--
-- Returns [] or ["U__BLOCKS__"]
--
getAppleBlocksOption :: IO [String]
getAppleBlocksOption = do
  let handler :: IOError -> IO String
      handler = (\_ -> return "")
  -- If file does not exist, we'll end up wth an empty string.
  fileContents <- catch (readFile "/usr/include/stdlib.h") handler
  return ["-U__BLOCKS__"  |  "__BLOCKS__" `isInfixOf` fileContents]

getCudaIncludePath :: CudaPath -> FilePath
getCudaIncludePath (CudaPath path) = path </> "include"

getCudaLibraryPath :: CudaPath -> Platform -> FilePath
getCudaLibraryPath (CudaPath path) (Platform arch os) = path </> libSubpath
  where
    libSubpath = case os of
      Windows -> "lib" </> case arch of
         I386   -> "Win32"
         X86_64 -> "x64"
         _      -> error $ printf "Unexpected Windows architecture %s.\nPlease report this issue to https://github.com/tmcdonell/cuda/issues\n" (show arch)

      OSX       -> "lib"

      -- For now just treat all other systems similarly
      _ -> case arch of
         X86_64 -> "lib64"
         I386   -> "lib"
         _      -> "lib"  -- TODO: how should this be handled?


-- On OS X we don't link against the CUDA and CUDART libraries directly.
-- Instead, we only link against CUDA.framework. This means that we will
-- not need to set the DYLD_LIBRARY_PATH environment variable in order to
-- compile or execute programs.
--
getCudaLibraries :: Platform -> [String]
getCudaLibraries (Platform _ os) =
  case os of
    OSX -> []
    _   -> ["cudart", "cuda"]


-- Slightly modified version of `words` from base - it takes predicate saying on which characters split.
splitOn :: (Char -> Bool) -> String -> [String]
splitOn p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : splitOn p s''
                            where (w, s'') = break p s'

-- Tries to obtain the version `ld`.
-- Throws an exception if failed.
--
getLdVersion :: Verbosity -> FilePath -> IO (Maybe [Int])
getLdVersion verbosity ldPath = do
  -- Version string format is like `GNU ld (GNU Binutils) 2.25.1`
  --                            or `GNU ld (GNU Binutils) 2.20.51.20100613`
  ldVersionString <- getProgramInvocationOutput normal (simpleProgramInvocation ldPath ["-v"])

  let versionText = last $ words ldVersionString -- takes e. g. "2.25.1"
  let versionParts = splitOn (== '.') versionText
  let versionParsed = Just $ map read versionParts

  -- last and read above may throw and message would be not understandable for user,
  -- so we'll intercept exception and rethrow it with more useful message.
  let handleError :: SomeException -> IO (Maybe [Int])
      handleError e = do
          warn verbosity $ printf "cannot parse ld version string: `%s`. Parsing exception: `%s`" ldVersionString (show e)
          return Nothing

  catch (evaluate versionParsed) handleError



-- On Windows GHC package comes with two copies of ld.exe.
-- ProgramDb knows about the first one - ghcpath\mingw\bin\ld.exe
-- This function returns the other one - ghcpath\mingw\x86_64-w64-mingw32\bin\ld.exe
-- The second one is the one that does actual linking and code generation.
-- See: https://github.com/tmcdonell/cuda/issues/31#issuecomment-149181376
--
-- The function is meant to be used only on 64-bit GHC distributions.
--
getRealLdPath :: Verbosity -> ProgramDb -> IO (Maybe FilePath)
getRealLdPath verbosity programDb =
  -- This should ideally work `programFindVersion ldProgram` but for some reason it does not.
  -- The issue should be investigated at some time.
  case lookupProgram ghcProgram programDb of
    Nothing -> return Nothing
    Just configuredGhc -> do
      let ghcPath        = locationPath $ programLocation configuredGhc
          presumedLdPath = (takeDirectory . takeDirectory) ghcPath </> "mingw" </> "x86_64-w64-mingw32" </> "bin" </> "ld.exe"
      info verbosity $ "Presuming ld location" ++ presumedLdPath
      presumedLdExists <- doesFileExist presumedLdPath
      return $ if presumedLdExists then Just presumedLdPath else Nothing

-- On Windows platform the binutils linker targeting x64 is bugged and cannot
-- properly link with import libraries generated by MS compiler (like the CUDA ones).
-- The programs would correctly compile and crash as soon as the first FFI call is made.
--
-- Therefore we fail configure process if the linker is too old and provide user
-- with guidelines on how to fix the problem.
--
validateLinker :: Verbosity -> Platform -> ProgramDb -> IO ()
validateLinker verbosity (Platform X86_64 Windows) db = do
  maybeLdPath <- getRealLdPath verbosity db
  case maybeLdPath of
    Nothing -> warn verbosity $ "Cannot find ld.exe to check if it is new enough. If generated executables crash when making calls to CUDA, please see " ++ helpfulPageLinkForWindows
    Just ldPath -> do
      debug verbosity $ "Checking if ld.exe at " ++ ldPath ++ " is new enough"
      maybeVersion <- getLdVersion verbosity ldPath
      case maybeVersion of
        Nothing -> warn verbosity $ "Unknown ld.exe version. If generated executables crash when making calls to CUDA, please see " ++ helpfulPageLinkForWindows
        Just ldVersion -> do
          debug verbosity $ "Found ld.exe version: " ++ show ldVersion
          when (ldVersion < [2,25,1]) $ die $ linkerBugOnWindowsMsg ldPath
validateLinker _ _ _ = return () -- The linker bug is present only on Win64 platform

helpfulPageLinkForWindows :: String
helpfulPageLinkForWindows = "https://github.com/tmcdonell/cuda/blob/master/WINDOWS.markdown"

linkerBugOnWindowsMsg :: FilePath -> String
linkerBugOnWindowsMsg ldPath = printf (unlines msg) ldPath
  where
    msg =
      [ "********************************************************************************"
      , ""
      , "The installed version of `ld.exe` has version < 2.25.1. This version has known bug on Windows x64 architecture, making it unable to correctly link programs using CUDA. The fix is available and MSys2 released fixed version of `ld.exe` as part of their binutils package (version 2.25.1)."
      , ""
      , "To fix this issue, replace the `ld.exe` in your GHC installation with the correct binary. See the following page for details:"
      , ""
      , "  " ++ helpfulPageLinkForWindows
      , ""
      , "The full path to the outdated `ld.exe` detected in your installation:"
      , ""
      , "> %s"
      , ""
      , "Please download a recent version of binutils `ld.exe`, from, e.g.:"
      , ""
      , "  http://repo.msys2.org/mingw/x86_64/mingw-w64-x86_64-binutils-2.25.1-1-any.pkg.tar.xz"
      , ""
      , "********************************************************************************"
      ]

-- Generates build info with flags needed for CUDA Toolkit to be properly
-- visible to underlying build tools.
--
cudaLibraryBuildInfo :: CudaPath -> Platform -> Version -> IO HookedBuildInfo
cudaLibraryBuildInfo cudaPath platform@(Platform arch os) ghcVersion = do
  let cudaLibraryPath   = getCudaLibraryPath cudaPath platform

  -- Extra lib dirs are not needed on Mac OS. On Windows or Linux their
  -- lack would cause an error: /usr/bin/ld: cannot find -lcudart
  let extraLibDirs_     = case os of
                            OSX     -> []
                            _       -> [cudaLibraryPath]

  let includeDirs       = [getCudaIncludePath cudaPath]
  let ccOptions_        = map ("-I" ++) includeDirs
  let ldOptions_        = map ("-L" ++) extraLibDirs_
  let ghcOptions        = map ("-optc" ++) ccOptions_  ++  map ("-optl" ++ ) ldOptions_
  let extraLibs_        = getCudaLibraries platform

  -- Options for C2HS
  let c2hsArchitectureFlag = case arch of
                               I386   -> ["-m32"]
                               X86_64 -> ["-m64"]
                               _      -> []
  let c2hsEmptyCaseFlag = ["-DUSE_EMPTY_CASE" | versionBranch ghcVersion >= [7,8]]
  let c2hsCppOptions    = c2hsArchitectureFlag ++ c2hsEmptyCaseFlag ++ ["-E"]

  let c2hsOptions       = unwords . map ("--cppopts=" ++)
  let extraOptionsC2Hs  = ("x-extra-c2hs-options", c2hsOptions c2hsCppOptions)
  let buildInfo         = emptyBuildInfo
          { ccOptions      = ccOptions_
          , ldOptions      = ldOptions_
          , extraLibs      = extraLibs_
          , extraLibDirs   = extraLibDirs_
          -- Are ghc-options below  needed for anything?
          -- On Windows they need to be disabled because Cabal does not escape
          -- them (quotes and backslashes) causing build fails on machines
          -- with CUDA_PATH containing spaces.
          , options        = [(GHC, ghcOptions) | os /= Windows]
          , customFieldsBI = [extraOptionsC2Hs]
          }

  let addSystemSpecificOptions :: Platform -> IO BuildInfo
      addSystemSpecificOptions (Platform _ Windows) = do
        -- Workaround issue with ghci linker not being able to find DLLs
        -- with names different from their import LIBs.
        extraGHCiLibs_ <- additionalGhciLibraries cudaLibraryPath extraLibs_
        return buildInfo { extraGHCiLibs = extraGHCiLibs  buildInfo ++ extraGHCiLibs_ }

      addSystemSpecificOptions (Platform _ OSX) = do
        -- On OS X tell the linker about the CUDA framework. It seems like
        -- this shouldn't be necessary, since we also specify this in the
        -- frameworks field. Possibly haskell/cabal#2724?
        --
        -- We also might need to add one or more options to c2hs cpp.
        appleBlocksOption <- getAppleBlocksOption
        return buildInfo
          { ldOptions      = ldOptions      buildInfo ++ ["-framework", "CUDA"]
          , customFieldsBI = unionWith (+++) []
                           $ customFieldsBI buildInfo ++ [("frameworks", "CUDA")
                                                         ,("x-extra-c2hs-options", c2hsOptions appleBlocksOption)]
          }

      addSystemSpecificOptions _ = return buildInfo

  adjustedBuildInfo <-addSystemSpecificOptions platform
  return (Just adjustedBuildInfo, [])


unionWith :: Ord k => (a -> a -> a) -> a -> [(k,a)] -> [(k,a)]
unionWith f z
  = map (\kv -> let (k,v) = unzip kv in (head k, foldr f z v))
  . groupBy ((==) `on` fst)
  . sortBy (compare `on` fst)

(+++) :: String -> String -> String
[] +++ ys = ys
xs +++ [] = xs
xs +++ ys = xs ++ ' ':ys


-- Checks whether given location looks like a valid CUDA toolkit directory
--
validateLocation :: Verbosity -> FilePath -> IO Bool
validateLocation verbosity path = do
  -- TODO: Ideally this should check also for cudart.lib and whether cudart
  -- exports relevant symbols. This should be achievable with some `nm`
  -- trickery
  let testedPath = path </> "include" </> "cuda.h"
  exists <- doesFileExist testedPath
  info verbosity $
    if exists
      then printf "Path accepted: %s\n" path
      else printf "Path rejected: %s\nDoes not exist: %s\n" path testedPath
  return exists

-- Evaluates IO to obtain the path, handling any possible exceptions.
-- If path is evaluable and points to valid CUDA toolkit returns True.
--
validateIOLocation :: Verbosity -> IO FilePath -> IO Bool
validateIOLocation verbosity iopath =
  let handler :: IOError -> IO Bool
      handler err = do
        info verbosity (show err)
        return False
  in
  catch (iopath >>= validateLocation verbosity) handler

-- Function iterates over action yielding possible locations, evaluating them
-- and returning the first valid one. Retuns Nothing if no location matches.
--
findFirstValidLocation :: Verbosity -> [(IO FilePath, String)] -> IO (Maybe FilePath)
findFirstValidLocation _         []                          = return Nothing
findFirstValidLocation verbosity ((locate,description):rest) = do
  info verbosity $ printf "checking for %s\n" description
  found <- validateIOLocation verbosity locate
  if found
    then Just `fmap` locate
    else findFirstValidLocation verbosity rest

nvccProgramName :: String
nvccProgramName = "nvcc"

-- NOTE: this function throws an exception when there is no `nvcc` in PATH.
-- The exception contains a meaningful message.
--
findProgramLocationThrowing :: String -> IO FilePath
findProgramLocationThrowing execName = do
  location <- findProgramLocation normal execName
  case location of
    Just validLocation -> return validLocation
    Nothing            -> ioError $ mkIOError doesNotExistErrorType ("not found: " ++ execName) Nothing Nothing

-- Returns pairs (action yielding candidate path, String description of that location)
--
candidateCudaLocation :: [(IO FilePath, String)]
candidateCudaLocation =
  [ env "CUDA_PATH"
  , (nvccLocation, "nvcc compiler in PATH")
  , defaultPath "/usr/local/cuda"
  ]
  where
    env s         = (getEnv s, printf "environment variable %s" s)
    defaultPath p = (return p, printf "default location %s" p)
    --
    nvccLocation :: IO FilePath
    nvccLocation = do
      nvccPath <- findProgramLocationThrowing nvccProgramName
      -- The obtained path is likely TOOLKIT/bin/nvcc
      -- We want to extract the TOOLKIT part
      let ret = takeDirectory $ takeDirectory nvccPath
      return ret


-- Try to locate CUDA installation on the drive.
-- Currently this means (in order)
--  1) Checking the CUDA_PATH environment variable
--  2) Looking for `nvcc` in `PATH`
--  3) Checking /usr/local/cuda
--
-- In case of failure, calls die with the pretty long message from below.
findCudaLocation :: Verbosity -> IO CudaPath
findCudaLocation verbosity = do
  firstValidLocation <- findFirstValidLocation verbosity candidateCudaLocation
  case firstValidLocation of
    Just validLocation -> do
      notice verbosity $ "Found CUDA toolkit at: " ++ validLocation
      return $ CudaPath validLocation
    Nothing -> die longError

longError :: String
longError = unlines
  [ "********************************************************************************"
  , ""
  , "The configuration process failed to locate your CUDA installation. Ensure that you have installed both the developer driver and toolkit, available from:"
  , ""
  , "> http://developer.nvidia.com/cuda-downloads"
  , ""
  , "and make sure that `nvcc` is available in your PATH. Check the above output log and run the command directly to ensure it can be located."
  , ""
  , "If you have a non-standard installation, you can add additional search paths using --extra-include-dirs and --extra-lib-dirs. Note that 64-bit Linux flavours often require both `lib64` and `lib` library paths, in that order."
  , ""
  , "********************************************************************************"
  ]


-- Runs CUDA detection procedure and stores .buildinfo to a file.
--
generateAndStoreBuildInfo :: Verbosity -> Platform -> CompilerId -> FilePath -> IO ()
generateAndStoreBuildInfo verbosity platform (CompilerId _ghcFlavor ghcVersion) path = do
  cudalocation <- findCudaLocation verbosity
  pbi          <- cudaLibraryBuildInfo cudalocation platform ghcVersion
  storeHookedBuildInfo verbosity path pbi

customBuildinfoFilepath :: FilePath
customBuildinfoFilepath = "cuda" <.> "buildinfo"

generatedBuldinfoFilepath :: FilePath
generatedBuldinfoFilepath = customBuildinfoFilepath <.> "generated"

main :: IO ()
main = defaultMainWithHooks customHooks
  where
    readHook :: (a -> Distribution.Simple.Setup.Flag Verbosity) -> Args -> a -> IO HookedBuildInfo
    readHook get_verbosity a flags = do
        noExtraFlags a
        getHookedBuildInfo verbosity
      where
        verbosity = fromFlag (get_verbosity flags)

    preprocessors = hookedPreProcessors simpleUserHooks

    -- Our readHook implementation usees our getHookedBuildInfo.
    -- We can't rely on cabal's autoconfUserHooks since they don't handle user
    -- overwrites to buildinfo like we do.
    customHooks   = simpleUserHooks
      { preBuild    = preBuildHook -- not using 'readHook' here because 'build' takes; extra args
      , preClean    = readHook cleanVerbosity
      , preCopy     = readHook copyVerbosity
      , preInst     = readHook installVerbosity
      , preHscolour = readHook hscolourVerbosity
      , preHaddock  = readHook haddockVerbosity
      , preReg      = readHook regVerbosity
      , preUnreg    = readHook regVerbosity
      , postConf    = postConfHook
      , hookedPreProcessors = ("chs", ppC2hs) : filter (\x -> fst x /= "chs") preprocessors
      }

    -- The hook just loads the HookedBuildInfo generated by postConfHook,
    -- unless there is user-provided info that overwrites it.
    preBuildHook :: Args -> BuildFlags -> IO HookedBuildInfo
    preBuildHook _ flags = getHookedBuildInfo $ fromFlag $ buildVerbosity flags

    -- The hook scans system in search for CUDA Toolkit. If the toolkit is not
    -- found, an error is raised. Otherwise the toolkit location is used to
    -- create a `cuda.buildinfo.generated` file with all the resulting flags.
    postConfHook :: Args -> ConfigFlags -> PackageDescription -> LocalBuildInfo -> IO ()
    postConfHook args flags pkg_descr lbi = do
      let
          verbosity = fromFlag (configVerbosity flags)
          currentPlatform = hostPlatform lbi
          compilerId_ = (compilerId $ compiler lbi)
      --
      noExtraFlags args
      generateAndStoreBuildInfo verbosity currentPlatform compilerId_ generatedBuldinfoFilepath
      validateLinker verbosity currentPlatform $ withPrograms lbi
      --
      actualBuildInfoToUse <- getHookedBuildInfo verbosity
      let pkg_descr' = updatePackageDescription actualBuildInfoToUse pkg_descr
      postConf simpleUserHooks args flags pkg_descr' lbi


storeHookedBuildInfo :: Verbosity -> FilePath -> HookedBuildInfo -> IO ()
storeHookedBuildInfo verbosity path hbi = do
    notice verbosity $ "Storing parameters to " ++ path
    writeHookedBuildInfo path hbi

-- Reads user-provided `cuda.buildinfo` if present, otherwise loads `cuda.buildinfo.generated`
-- Outputs message informing about the other possibility.
-- Calls die when neither of the files is available.
-- (generated one should be always present, as it is created in the post-conf step)
--
getHookedBuildInfo :: Verbosity -> IO HookedBuildInfo
getHookedBuildInfo verbosity = do
  doesCustomBuildInfoExists <- doesFileExist customBuildinfoFilepath
  if doesCustomBuildInfoExists
    then do
      notice verbosity $ printf "The user-provided buildinfo from file %s will be used. To use default settings, delete this file.\n" customBuildinfoFilepath
      readHookedBuildInfo verbosity customBuildinfoFilepath
    else do
      doesGeneratedBuildInfoExists <- doesFileExist generatedBuldinfoFilepath
      if doesGeneratedBuildInfoExists
        then do
          notice verbosity $ printf "Using build information from '%s'.\n" generatedBuldinfoFilepath
          notice verbosity $ printf "Provide a '%s' file to override this behaviour.\n" customBuildinfoFilepath
          readHookedBuildInfo verbosity generatedBuldinfoFilepath
        else
          die $ printf "Unexpected failure. Neither the default %s nor custom %s exist.\n" generatedBuldinfoFilepath customBuildinfoFilepath


-- Replicate the default C2HS preprocessor hook here, and inject a value for
-- extra-c2hs-options, if it was present in the buildinfo file
--
-- Everything below copied from Distribution.Simple.PreProcess
--
ppC2hs :: BuildInfo -> LocalBuildInfo -> PreProcessor
ppC2hs bi lbi
    = PreProcessor {
        platformIndependent = False,
        runPreProcessor     = \(inBaseDir, inRelativeFile)
                               (outBaseDir, outRelativeFile) verbosity ->
          rawSystemProgramConf verbosity c2hsProgram (withPrograms lbi) . filter (not . null) $
            maybe [] words (lookup "x-extra-c2hs-options" (customFieldsBI bi))
            ++ ["--include=" ++ outBaseDir]
            ++ ["--cppopts=" ++ opt | opt <- getCppOptions bi lbi]
            ++ ["--output-dir=" ++ outBaseDir,
                "--output=" ++ outRelativeFile,
                inBaseDir </> inRelativeFile]
      }

getCppOptions :: BuildInfo -> LocalBuildInfo -> [String]
getCppOptions bi lbi
    = hcDefines (compiler lbi)
   ++ ["-I" ++ dir | dir <- includeDirs bi]
   ++ [opt | opt@('-':c:_) <- ccOptions bi, c `elem` "DIU"]

hcDefines :: Compiler -> [String]
hcDefines comp =
  case compilerFlavor comp of
    GHC  -> ["-D__GLASGOW_HASKELL__=" ++ versionInt version]
    JHC  -> ["-D__JHC__=" ++ versionInt version]
    NHC  -> ["-D__NHC__=" ++ versionInt version]
    Hugs -> ["-D__HUGS__"]
    _    -> []
  where version = compilerVersion comp

-- TODO: move this into the compiler abstraction
-- FIXME: this forces GHC's crazy 4.8.2 -> 408 convention on all the other
-- compilers. Check if that's really what they want.
versionInt :: Version -> String
versionInt (Version { versionBranch = [] }) = "1"
versionInt (Version { versionBranch = [n] }) = show n
versionInt (Version { versionBranch = n1:n2:_ })
  = -- 6.8.x -> 608
    -- 6.10.x -> 610
    let s1 = show n1
        s2 = show n2
        middle = case s2 of
                 _ : _ : _ -> ""
                 _         -> "0"
    in s1 ++ middle ++ s2

