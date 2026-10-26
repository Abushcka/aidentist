package kg.aidentist.app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Message;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

/**
 * AI Dentist — оболочка над веб-панелью клиники.
 * При запуске показывает экран выбора клиники (assets/launcher), затем открывает панель
 * https://<клиника>… в WebView. Чужие ссылки (WhatsApp, Telegram, телефон) и файлы (/api/…: PDF, снимки)
 * открываются во внешних приложениях.
 */
public class MainActivity extends Activity {

    private static final String LAUNCHER = "file:///android_asset/launcher/index.html";
    private static final String ASSETS = "file:///android_asset/";
    private static final int FILE_REQUEST = 1001;
    private static final int BRAND = Color.rgb(22, 105, 90);

    private WebView web;
    private SharedPreferences prefs;
    private ValueCallback<Uri[]> fileCallback;
    private volatile String currentUrl = "";
    private boolean clearHistoryOnNextClinicPage = false;

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("aidentist", MODE_PRIVATE);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(BRAND);
        web = new WebView(this);
        web.setBackgroundColor(BRAND);
        root.addView(web, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);

        // Android 11+: рисуем под системными панелями сами и отступаем на их высоту (и на клавиатуру).
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            root.setOnApplyWindowInsetsListener((v, insets) -> {
                Insets i = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                v.setPadding(i.left, i.top, i.right, i.bottom);
                return WindowInsets.CONSUMED;
            });
        }

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(true);          // только для экрана выбора клиники из assets
        s.setAllowContentAccess(false);
        s.setSupportMultipleWindows(true);   // target=_blank / window.open → внешнее приложение
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setUserAgentString(s.getUserAgentString() + " AIDentistApp/" + appVersion() + " (Android)");

        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);

        web.addJavascriptInterface(new Bridge(), "AIDentistNative");
        web.setWebViewClient(new Client());
        web.setWebChromeClient(new Chrome());
        web.setDownloadListener((url, ua, cd, mime, len) -> openExternal(Uri.parse(url)));

        if (savedInstanceState != null) web.restoreState(savedInstanceState);
        else web.loadUrl(LAUNCHER);
    }

    // ---------- мост для экрана выбора клиники ----------
    private class Bridge {
        @JavascriptInterface
        public String getClinic() { return prefs.getString("clinic", ""); }

        @JavascriptInterface
        public void setClinic(String url) {
            if (!currentUrl.startsWith(ASSETS)) return;           // менять клинику может только наш экран
            Uri u = Uri.parse(url == null ? "" : url.trim());
            if (!"https".equals(u.getScheme()) || u.getHost() == null || u.getHost().isEmpty()) return;
            String origin = "https://" + u.getHost() + (u.getPort() > 0 ? ":" + u.getPort() : "");
            prefs.edit().putString("clinic", origin).apply();
            runOnUiThread(() -> {
                clearHistoryOnNextClinicPage = true;
                web.loadUrl(origin + "/");
            });
        }
    }

    private String clinicHost() {
        String c = prefs.getString("clinic", "");
        return c.isEmpty() ? null : Uri.parse(c).getHost();
    }

    private boolean isClinic(Uri u) {
        String h = clinicHost();
        return h != null && "https".equals(u.getScheme()) && h.equalsIgnoreCase(u.getHost());
    }

    // ---------- навигация ----------
    private class Client extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
            if (!req.isForMainFrame()) return false;
            Uri u = req.getUrl();
            String url = u.toString();
            if (url.startsWith(ASSETS)) return false;
            if (isClinic(u)) {
                String p = u.getPath();
                if (p != null && p.startsWith("/api/")) { openExternal(u); return true; } // PDF, файлы пациента
                return false;
            }
            openExternal(u);
            return true;
        }

        @Override
        public void onPageStarted(WebView view, String url, Bitmap favicon) {
            currentUrl = url == null ? "" : url;
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            currentUrl = url == null ? "" : url;
            if (clearHistoryOnNextClinicPage && url != null && isClinic(Uri.parse(url))) {
                view.clearHistory();
                clearHistoryOnNextClinicPage = false;
            }
            CookieManager.getInstance().flush();
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError err) {
            if (req.isForMainFrame() && isClinic(req.getUrl())) view.loadUrl(LAUNCHER + "?error=1");
        }

        @Override
        public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
            recreate();
            return true;
        }
    }

    // ---------- окна, выбор файлов ----------
    private class Chrome extends WebChromeClient {
        @Override
        public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
            // Новое окно (target=_blank, window.open): ловим его адрес и открываем снаружи.
            WebView tmp = new WebView(MainActivity.this);
            tmp.setWebViewClient(new WebViewClient() {
                boolean done = false;
                private void take(WebView v, String url) {
                    if (done || url == null || url.isEmpty() || url.startsWith("about:")) return;
                    done = true;
                    openExternal(Uri.parse(url));
                    v.stopLoading();
                    v.post(v::destroy);
                }
                @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { take(v, r.getUrl().toString()); return true; }
                @Override public void onPageStarted(WebView v, String url, Bitmap f) { take(v, url); }
            });
            ((WebView.WebViewTransport) resultMsg.obj).setWebView(tmp);
            resultMsg.sendToTarget();
            return true;
        }

        @Override
        public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
            if (fileCallback != null) fileCallback.onReceiveValue(null);
            fileCallback = callback;
            Intent i = params.createIntent();
            i.addCategory(Intent.CATEGORY_OPENABLE);
            if (params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE) i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
            String[] types = params.getAcceptTypes();
            if (types != null && types.length > 1) {
                i.setType("*/*");
                i.putExtra(Intent.EXTRA_MIME_TYPES, types);
            }
            try {
                startActivityForResult(Intent.createChooser(i, "Выберите файл"), FILE_REQUEST);
            } catch (ActivityNotFoundException e) {
                fileCallback = null;
                return false;
            }
            return true;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != FILE_REQUEST) { super.onActivityResult(requestCode, resultCode, data); return; }
        if (fileCallback == null) return;
        Uri[] result = null;
        if (resultCode == RESULT_OK && data != null) {
            ClipData clip = data.getClipData();
            if (clip != null && clip.getItemCount() > 0) {
                result = new Uri[clip.getItemCount()];
                for (int k = 0; k < clip.getItemCount(); k++) result[k] = clip.getItemAt(k).getUri();
            } else if (data.getData() != null) {
                result = new Uri[]{data.getData()};
            }
        }
        fileCallback.onReceiveValue(result);
        fileCallback = null;
    }

    private void openExternal(Uri u) {
        try {
            Intent i;
            if ("intent".equals(u.getScheme())) i = Intent.parseUri(u.toString(), Intent.URI_INTENT_SCHEME);
            else i = new Intent(Intent.ACTION_VIEW, u);
            i.addCategory(Intent.CATEGORY_BROWSABLE);
            i.setComponent(null);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Exception e) {
            Toast.makeText(this, "Не найдено приложение, чтобы открыть ссылку", Toast.LENGTH_SHORT).show();
        }
    }

    // ---------- кнопка «Назад» ----------
    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (web.canGoBack()) { web.goBack(); return; }
        if (currentUrl.startsWith(ASSETS)) { super.onBackPressed(); return; }
        new AlertDialog.Builder(this)
                .setTitle("AI Dentist")
                .setMessage("Выйти из приложения?")
                .setPositiveButton("Выйти", (d, w) -> finish())
                .setNeutralButton("Сменить клинику", (d, w) -> web.loadUrl(LAUNCHER + "?change=1"))
                .setNegativeButton("Отмена", null)
                .show();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override protected void onResume() { super.onResume(); web.onResume(); }
    @Override protected void onPause() { web.onPause(); CookieManager.getInstance().flush(); super.onPause(); }

    @Override
    protected void onDestroy() {
        if (web != null) {
            ((ViewGroup) web.getParent()).removeView(web);
            web.destroy();
        }
        super.onDestroy();
    }

    private String appVersion() {
        try { return getPackageManager().getPackageInfo(getPackageName(), 0).versionName; }
        catch (Exception e) { return "1.0"; }
    }
}
