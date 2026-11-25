.class public Lcom/rentmanager/app/MainActivity$Chrome;
.super Landroid/webkit/WebChromeClient;
.source "MainActivity.java"


# instance fields
.field private final a:Lcom/rentmanager/app/MainActivity;


# direct methods
.method public constructor <init>(Lcom/rentmanager/app/MainActivity;)V
    .locals 0

    invoke-direct {p0}, Landroid/webkit/WebChromeClient;-><init>()V

    iput-object p1, p0, Lcom/rentmanager/app/MainActivity$Chrome;->a:Lcom/rentmanager/app/MainActivity;

    return-void
.end method


# virtual methods
.method public onShowFileChooser(Landroid/webkit/WebView;Landroid/webkit/ValueCallback;Landroid/webkit/WebChromeClient$FileChooserParams;)Z
    .locals 2

    invoke-virtual {p3}, Landroid/webkit/WebChromeClient$FileChooserParams;->createIntent()Landroid/content/Intent;

    move-result-object v0

    iget-object v1, p0, Lcom/rentmanager/app/MainActivity$Chrome;->a:Lcom/rentmanager/app/MainActivity;

    invoke-virtual {v1, p2, v0}, Lcom/rentmanager/app/MainActivity;->pickFile(Landroid/webkit/ValueCallback;Landroid/content/Intent;)V

    const/4 v0, 0x1

    return v0
.end method
