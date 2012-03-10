AmazonS3.put("pixlpaste", "test", "text/plain", "hello world")
Debug.warning(AmazonS3.get("pixlpaste", "test"))
AmazonS3.delete("pixlpaste", "test")
