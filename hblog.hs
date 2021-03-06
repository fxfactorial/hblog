--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

import Hakyll
import Data.Monoid
import Data.List (isInfixOf)
import System.FilePath.Posix  (takeBaseName,takeDirectory,(</>),splitFileName)
import Text.Pandoc

--------------------------------------------------------------------------------
main :: IO ()
main = hakyllWith config $ do
  tags <- buildTags "posts/*" (fromCapture "tags/*")

  match (fromList staticFiles) $ do
    route idRoute
    compile copyFileCompiler
  
  match "images/*" $ do
    route   idRoute
    compile copyFileCompiler

  match "css/main.scss" $ do
    route $ setExtension "css"
    compile $ getResourceString >>= sassify

  match "notes/*" $ do
    route noteRoute
    compile $ pandocCompilerWith defaultHakyllReaderOptions pandocTocWriter
      >>= loadAndApplyTemplate "templates/page-with-toc.html" defaultContext
      >>= loadAndApplyTemplate "templates/default.html" defaultContext
      >>= relativizeUrls
      >>= removeIndexHtml

  match "about.markdown" $ do
    route niceRoute
    compile $ pandocCompilerWith defaultHakyllReaderOptions pandocTocWriter
      >>= loadAndApplyTemplate "templates/page-with-toc.html" defaultContext
      >>= loadAndApplyTemplate "templates/default.html" defaultContext
      >>= relativizeUrls
      >>= removeIndexHtml

  match "posts/*" $ do
    route niceDateRoute
    compile $ pandocCompiler
      >>= saveSnapshot "content"
      >>= loadAndApplyTemplate "templates/post.html" (postCtx tags)
      >>= loadAndApplyTemplate "templates/default.html" (postCtx tags)
      >>= relativizeUrls
      >>= removeIndexHtml

  match "talks/*" $ do
    route talkRoute
    compile $ pandocCompiler
      >>= loadAndApplyTemplate "templates/talk.html" talkCtx
      >>= loadAndApplyTemplate "templates/default.html" talkCtx
      >>= relativizeUrls
      >>= removeIndexHtml

  create ["archive.html"] $ do
    route niceRoute
    compile $ do
      let archiveCtx =
            field "posts" (\_ -> postList tags recentFirst)   `mappend`
            constField "title" "Archive"                      `mappend`
            defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
        >>= loadAndApplyTemplate "templates/default.html" archiveCtx
        >>= relativizeUrls
        >>= removeIndexHtml

  create ["notes.html"] $ do
    route niceRoute
    compile $ do
      let noteCtx =
            field "notes" (const noteList) `mappend`
            constField "title" "Notes"     `mappend`
            defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/notes.html" noteCtx
        >>= loadAndApplyTemplate "templates/default.html" noteCtx
        >>= relativizeUrls
        >>= removeIndexHtml

  create ["talks.html"] $ do
    route niceRoute
    compile $ do
      let talksCtx =
            field "talks" (\_ -> talkList recentFirst) `mappend`
            constField "title" "Talks"                 `mappend`
            defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/talks.html" talksCtx
        >>= loadAndApplyTemplate "templates/default.html" talksCtx
        >>= removeIndexHtml

  create ["atom.xml"] $ do
    route idRoute
    compile $ do
      loadAllSnapshots "posts/*" "content"
        >>= fmap (take 10) . recentFirst
        >>= renderRss (feedConfiguration "All posts") feedCtx
        
  match "index.html" $ do
    route idRoute
    compile $ do
      let indexCtx = field "posts" $ \_ ->
            completePostList tags $ fmap (take 5) . recentFirst

      getResourceBody
        >>= applyAsTemplate indexCtx
        >>= loadAndApplyTemplate "templates/default.html" (postCtx tags)
        >>= relativizeUrls
        >>= removeIndexHtml

  tagsRules tags $ \tag pattern -> do
    let title = "Posts tagged " ++ tag

    route niceRoute
    compile $ do
      posts <- recentFirst =<< loadAll pattern
      let ctx = constField "title" title <>
                listField "posts" (postCtx tags) (return posts) <>
                defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/tag.html" ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls
        >>= removeIndexHtml

  match "templates/*" $ compile templateCompiler

  where pandocTocWriter = defaultHakyllWriterOptions { writerTableOfContents = True
                                                     , writerTemplate = Just "$if(toc)$ $toc$ $endif$\n$body$"}
        staticFiles = ["CNAME", "humans.txt", "robots.txt", "favicon.ico"]
      

--------------------------------------------------------------------------------
postCtx :: Tags -> Context String
postCtx tags = mconcat
               [ dateField "date" "%B %e, %Y"
               , tagsField "tags" tags
               , defaultContext
               ]

--------------------------------------------------------------------------------
talkCtx :: Context String
talkCtx = mconcat
          [ dateField "date" "%B %e, %Y"
          , defaultContext
          ]
--------------------------------------------------------------------------------
postList :: Tags -> ([Item String] -> Compiler [Item String]) -> Compiler String
postList tags sortFilter = do
  posts   <- sortFilter =<< loadAll "posts/*"
  itemTpl <- loadBody "templates/post-item.html"
  applyTemplateList itemTpl (postCtx tags) posts

--------------------------------------------------------------------------------
noteList ::  Compiler String
noteList = do
  posts   <- loadAll "notes/*"
  itemTpl <- loadBody "templates/post-item.html"
  applyTemplateList itemTpl defaultContext posts

--------------------------------------------------------------------------------
talkList ::  ([Item String] -> Compiler [Item String]) -> Compiler String
talkList sortFilter = do
  talks   <- sortFilter =<< loadAll "talks/*"
  itemTpl <- loadBody "templates/post-item.html"
  applyTemplateList itemTpl defaultContext talks
  
--------------------------------------------------------------------------------
-- | Returns a list of post bodies
completePostList :: Tags -> ([Item String] -> Compiler [Item String]) -> Compiler String
completePostList tags sortFilter = do
  posts   <- sortFilter =<< loadAllSnapshots "posts/*" "content"
  itemTpl <- loadBody "templates/post-with-link.html"
  applyTemplateList itemTpl (postCtx tags) posts

--------------------------------------------------------------------------------
dateRoute :: Routes
dateRoute = gsubRoute "posts/" (const "") `composeRoutes`
            gsubRoute "[0-9]{4}-[0-9]{2}-[0-9]{2}-" (map replaceChars)
  where
    replaceChars c | c == '-' || c == '_' = '/'
                   | otherwise = c

--------------------------------------------------------------------------------
talkRoute :: Routes
talkRoute = gsubRoute  "[0-9]{4}-[0-9]{2}-[0-9]{2}-" (const "") `composeRoutes`
            niceRoute
--------------------------------------------------------------------------------
niceRoute :: Routes
niceRoute = customRoute createIndexRoute
  where
    createIndexRoute ident =
      takeDirectory p </> takeBaseName p </> "index.html"
      where
        p = toFilePath ident
        
--------------------------------------------------------------------------------
-- |Turns 2012-02-01-post.html into 2012/02/01/post/index.html
niceDateRoute :: Routes
niceDateRoute = composeRoutes dateRoute niceRoute

--------------------------------------------------------------------------------
-- | Turns notes/post.html into /post/index.html
noteRoute :: Routes
noteRoute = gsubRoute "notes/" (const "") `composeRoutes` niceRoute

--------------------------------------------------------------------------------
-- |Replace an url of the form foo/bar/index.html by foo/bar
removeIndexHtml :: Item String -> Compiler (Item String)
removeIndexHtml item = return $ fmap (withUrls removeIndexStr) item

--------------------------------------------------------------------------------
-- |Removes the .html component of a URL if it is local
removeIndexStr :: String -> String
removeIndexStr url = case splitFileName url of
  (dir, "index.html") | isLocal dir -> dir
                      | otherwise   -> url
  _                                 -> url
  where
    isLocal uri = not ("://" `isInfixOf` uri)
      
--------------------------------------------------------------------------------
-- |Run sass and compress the result
sassify :: Item String -> Compiler (Item String)
sassify item = withItemBody (unixFilter "sass" ["-s", "--scss", "--load-path", "css"]) item
               >>= return . fmap compressCss

--------------------------------------------------------------------------------
-- | Feeds

feedCtx :: Context String
feedCtx = mconcat
          [ bodyField "description"
          , defaultContext
          ]

feedConfiguration :: String -> FeedConfiguration
feedConfiguration title = FeedConfiguration
                          { feedTitle       = "hyegar.com - " ++ title
                          , feedDescription = "Personal blog of Edgar Aroutiounian"
                          , feedAuthorName  = "Edgar Aroutiounian"
                          , feedAuthorEmail = "edgar@beancode.io"
                          , feedRoot        = "http://hyegar.com"
                          }

--------------------------------------------------------------------------------
-- | Deployment
config :: Configuration
config = defaultConfiguration { deployCommand = deployScript }

deployScript :: String
deployScript = "echo \"-- Publishing to hyegar.com\" &&\
               \echo \"-- Rebuilding site...\" && \
               \./hblog rebuild && \
               \cd _publish && \
               \echo \"-- Updating deploy repository...\" && \
               \git fetch github && \
               \git reset --hard github/master && \
               \echo \"-- Adding new files to deploy repository...\" && \
               \rm -rf * && \
               \cp -r ../_site/* . && \
               \echo \"-- Commiting changes\" && \
               \dt=`date -u \"+%Y-%m-%d %H:%M:%S %Z\"` && \
               \message=\"Site update at $dt\" && \
               \git add . && \
               \git commit -m\"$message\" && \
               \echo \"-- Deploying site\" && \
               \git push github master && \
               \echo \"-- Site published\""
